import Foundation

struct CameraIntrinsics: Codable {
    let fx, fy, cx, cy: Float
    let width, height: Int
}

struct FrameMetadata: Codable, Identifiable {
    let id: Int
    let timestamp: Double
    let intrinsics: CameraIntrinsics
    let transform: [Float]               // 4×4 column-major (camera→world)
    let planeNormal: [Float]?
    let planeDistance: Float?
    let cameraHeightAbovePlane: Float?
    let hasLidar: Bool
    let pitchScore: Float
}

struct SessionMetadata: Codable {
    let sessionId: String
    let startTime: Double
    let endTime: Double
    let frameCount: Int
    let hasLidar: Bool
}
