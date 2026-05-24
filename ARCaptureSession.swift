import ARKit
import UIKit
import simd
import Combine

class ARCaptureSession: NSObject, ObservableObject {

    let arSession = ARSession()

    @Published var pitchScore: Float = 0
    @Published var pitchDegrees: Float = 0
    @Published var isGoodAngle: Bool = false
    @Published var hasPlane: Bool = false
    @Published var previewImage: UIImage?
    @Published var cameraHeightCm: Float?

    // Scan state
    @Published var isScanning: Bool = false
    @Published var scanFrameCount: Int = 0
    @Published var scanElapsed: TimeInterval = 0

    let hasLidar: Bool
    let goodAngleThreshold: Float = 0.65
    let maxScanDuration: TimeInterval = 6.0
    let captureInterval: TimeInterval = 0.4   // 초당 약 2.5 프레임

    var onCapture: ((ARFrame, ARPlaneAnchor?) -> Void)?
    var onScanComplete: (() -> Void)?

    private var bestPlane: ARPlaneAnchor?
    private var previewTick = 0
    private var scanStartTime: Date?
    private var lastCaptureTime: Date?
    private var scanTimer: Timer?

    override init() {
        hasLidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        super.init()
        arSession.delegate = self
        startSession()
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if hasLidar {
            config.frameSemantics = [.sceneDepth]
        }
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanFrameCount = 0
        scanStartTime = Date()
        lastCaptureTime = nil

        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.scanStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            DispatchQueue.main.async { self.scanElapsed = elapsed }
            if elapsed >= self.maxScanDuration {
                self.stopScan()
            }
        }
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        onScanComplete?()
    }

    // MARK: - Helpers

    private func computePitchScore(_ t: simd_float4x4) -> Float {
        let lookDir = simd_float3(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)
        return max(0, simd_dot(simd_normalize(lookDir), simd_float3(0, -1, 0)))
    }

    private func computeHeight(_ cameraTransform: simd_float4x4,
                                _ plane: ARPlaneAnchor) -> Float {
        let camPos = simd_float3(cameraTransform.columns.3.x,
                                 cameraTransform.columns.3.y,
                                 cameraTransform.columns.3.z)
        let pt = plane.transform
        let normal = simd_normalize(simd_float3(pt.columns.1.x,
                                                pt.columns.1.y,
                                                pt.columns.1.z))
        let planeOrigin = simd_float3(pt.columns.3.x, pt.columns.3.y, pt.columns.3.z)
        return abs(simd_dot(camPos - planeOrigin, normal))
    }

    private func makePreview(_ buffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }
}

// MARK: - ARSessionDelegate
extension ARCaptureSession: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let score = computePitchScore(frame.camera.transform)
        let height = bestPlane.map { computeHeight(frame.camera.transform, $0) }

        previewTick += 1
        let img: UIImage? = previewTick % 20 == 0 ? makePreview(frame.capturedImage) : nil

        // 스캔 중이면 captureInterval마다 자동 캡처 (각도 무관)
        if isScanning {
            let now = Date()
            let ready = lastCaptureTime == nil ||
                now.timeIntervalSince(lastCaptureTime!) >= captureInterval
            if ready {
                lastCaptureTime = now
                onCapture?(frame, bestPlane)
                DispatchQueue.main.async { self.scanFrameCount += 1 }
            }
        }

        DispatchQueue.main.async {
            self.pitchScore = score
            self.pitchDegrees = asin(min(1, score)) * 180 / .pi
            self.isGoodAngle = score >= self.goodAngleThreshold
            self.cameraHeightCm = height.map { $0 * 100 }
            if let img { self.previewImage = img }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .horizontal else { continue }
            if bestPlane == nil {
                bestPlane = plane
                DispatchQueue.main.async { self.hasPlane = true }
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let plane = anchor as? ARPlaneAnchor,
               plane.identifier == bestPlane?.identifier {
                bestPlane = plane
            }
        }
    }
}
