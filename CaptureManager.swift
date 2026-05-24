import ARKit
import UIKit
import simd
import Combine

class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var currentSessionFrameCount: Int = 0
    @Published var savedSessions: [String] = []

    private var currentSessionDir: URL?
    private var sessionFrameIndex: Int = 0

    var captureBaseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ARCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Session lifecycle

    func startSession() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let sessionId = "session_\(fmt.string(from: Date()))"

        let sessionDir = captureBaseDir.appendingPathComponent(sessionId)
        try? FileManager.default.createDirectory(at: sessionDir,
                                                  withIntermediateDirectories: true)
        currentSessionDir = sessionDir
        sessionFrameIndex = 0
        DispatchQueue.main.async { self.currentSessionFrameCount = 0 }
        return sessionId
    }

    func saveFrame(_ frame: ARFrame, plane: ARPlaneAnchor?) {
        guard let sessionDir = currentSessionDir else { return }

        let idx = sessionFrameIndex
        sessionFrameIndex += 1

        let frameDir = sessionDir.appendingPathComponent(String(format: "frame_%04d", idx))
        try? FileManager.default.createDirectory(at: frameDir,
                                                  withIntermediateDirectories: true)

        saveRGB(frame.capturedImage, to: frameDir.appendingPathComponent("rgb.jpg"))

        let hasLidar = frame.sceneDepth != nil
        if let sd = frame.sceneDepth {
            saveDepth(sd.depthMap, to: frameDir.appendingPathComponent("depth.bin"))
            if let conf = sd.confidenceMap {
                saveConfidence(conf, to: frameDir.appendingPathComponent("confidence.bin"))
            }
        }

        let meta = buildMetadata(frame: frame, plane: plane, index: idx, hasLidar: hasLidar)
        if let data = try? JSONEncoder().encode(meta),
           let str = String(data: data, encoding: .utf8) {
            try? str.write(to: frameDir.appendingPathComponent("metadata.json"),
                           atomically: true, encoding: .utf8)
        }

        DispatchQueue.main.async { self.currentSessionFrameCount += 1 }
    }

    func endSession(sessionId: String, startTime: Date) {
        guard let sessionDir = currentSessionDir else { return }

        let meta = SessionMetadata(
            sessionId: sessionId,
            startTime: startTime.timeIntervalSince1970,
            endTime: Date().timeIntervalSince1970,
            frameCount: sessionFrameIndex,
            hasLidar: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        )
        if let data = try? JSONEncoder().encode(meta),
           let str = String(data: data, encoding: .utf8) {
            try? str.write(to: sessionDir.appendingPathComponent("session_meta.json"),
                           atomically: true, encoding: .utf8)
        }

        DispatchQueue.main.async { self.savedSessions.append(sessionId) }
        currentSessionDir = nil
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: captureBaseDir)
        DispatchQueue.main.async {
            self.savedSessions = []
            self.currentSessionFrameCount = 0
        }
    }

    // MARK: - Metadata builder

    private func buildMetadata(frame: ARFrame, plane: ARPlaneAnchor?,
                                index: Int, hasLidar: Bool) -> FrameMetadata {
        let t = frame.camera.transform
        let intr = frame.camera.intrinsics
        let sz = frame.camera.imageResolution

        let transform: [Float] = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w,
        ]

        var planeNormal: [Float]? = nil
        var planeDist: Float? = nil
        var camHeight: Float? = nil

        if let plane = plane {
            let pt = plane.transform
            let n = simd_normalize(simd_float3(pt.columns.1.x,
                                               pt.columns.1.y,
                                               pt.columns.1.z))
            planeNormal = [n.x, n.y, n.z]
            let po = simd_float3(pt.columns.3.x, pt.columns.3.y, pt.columns.3.z)
            let cp = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            planeDist = simd_dot(cp - po, n)
            camHeight = abs(planeDist ?? 0)
        }

        let lookDir = simd_float3(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)
        let pitchScore = max(0, simd_dot(simd_normalize(lookDir), simd_float3(0, -1, 0)))

        return FrameMetadata(
            id: index,
            timestamp: frame.timestamp,
            intrinsics: CameraIntrinsics(
                fx: intr[0][0], fy: intr[1][1],
                cx: intr[2][0], cy: intr[2][1],
                width: Int(sz.width), height: Int(sz.height)
            ),
            transform: transform,
            planeNormal: planeNormal,
            planeDistance: planeDist,
            cameraHeightAbovePlane: camHeight,
            hasLidar: hasLidar,
            pitchScore: pitchScore
        )
    }

    // MARK: - File writers

    private func saveRGB(_ buffer: CVPixelBuffer, to url: URL) {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let img = UIImage(cgImage: cg, scale: 1, orientation: .right)
        try? img.jpegData(compressionQuality: 0.92)?.write(to: url)
    }

    /// float32 깊이 (meters), 헤더: width(Int32) + height(Int32) + data
    private func saveDepth(_ buffer: CVPixelBuffer, to url: URL) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)

        var data = Data(capacity: 8 + h * w * 4)
        var wi = Int32(w), hi = Int32(h)
        data.append(contentsOf: withUnsafeBytes(of: &wi, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: &hi, Array.init))
        for row in 0..<h {
            data.append(Data(bytes: base.advanced(by: row * bpr), count: w * 4))
        }
        try? data.write(to: url)
    }

    /// uint8 신뢰도 (0=low,1=med,2=high), 동일 헤더
    private func saveConfidence(_ buffer: CVPixelBuffer, to url: URL) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)

        var data = Data(capacity: 8 + h * w)
        var wi = Int32(w), hi = Int32(h)
        data.append(contentsOf: withUnsafeBytes(of: &wi, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: &hi, Array.init))
        for row in 0..<h {
            data.append(Data(bytes: base.advanced(by: row * bpr), count: w))
        }
        try? data.write(to: url)
    }
}
