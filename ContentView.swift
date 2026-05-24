import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var arSession = ARCaptureSession()
    @StateObject private var capture = CaptureManager.shared

    @State private var currentSessionId: String?
    @State private var currentSessionStart: Date?
    @State private var showCompleteBanner = false
    @State private var blinkOn = false

    var body: some View {
        ZStack {
            ARPreviewView(arSession: arSession)
                .ignoresSafeArea()

            VStack {
                topBar
                    .padding(.top, 60)
                    .padding(.horizontal)
                Spacer()
                bottomPanel
                    .padding(.bottom, 44)
                    .padding(.horizontal)
            }

            if showCompleteBanner {
                completeBanner
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            arSession.onCapture = { frame, plane in
                capture.saveFrame(frame, plane: plane)
            }
            arSession.onScanComplete = {
                if let id = currentSessionId, let start = currentSessionStart {
                    capture.endSession(sessionId: id, startTime: start)
                }
                withAnimation(.spring()) { showCompleteBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showCompleteBanner = false }
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Label(
                arSession.hasPlane ? "테이블 감지됨" : "테이블 찾는 중...",
                systemImage: arSession.hasPlane ? "checkmark.circle.fill" : "circle.dashed"
            )
            .foregroundColor(arSession.hasPlane ? .green : .yellow)
            .font(.caption.bold())

            Spacer()

            if let h = arSession.cameraHeightCm {
                Text(String(format: "높이 %.0f cm", h))
                    .foregroundColor(.white)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.black.opacity(0.4))
        .cornerRadius(12)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        Group {
            if arSession.isScanning {
                scanningPanel
            } else {
                idlePanel
            }
        }
    }

    private var idlePanel: some View {
        VStack(spacing: 14) {
            angleBar

            Text(String(format: "%.0f° 내려보는 중", arSession.pitchDegrees))
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

            Button(action: startScan) {
                Label("스캔 시작", systemImage: "camera.fill")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 220, height: 56)
                    .background(arSession.hasPlane ? Color.red : Color.gray)
                    .cornerRadius(28)
            }
            .disabled(!arSession.hasPlane)

            Text(arSession.hasPlane
                 ? "음식 주위를 천천히 이동하며 촬영하세요"
                 : "카메라를 테이블 방향으로 향해주세요")
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    private var scanningPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(blinkOn ? 1 : 0.15)
                    .onAppear {
                        blinkOn = false
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            blinkOn = true
                        }
                    }
                    .onDisappear { blinkOn = false }
                Text("스캔 중")
                    .font(.headline.bold())
                    .foregroundColor(.red)
            }

            HStack(spacing: 32) {
                statCell(value: "\(capture.currentSessionFrameCount)", label: "프레임")
                statCell(value: String(format: "%.1fs", arSession.scanElapsed), label: "경과")
            }

            ProgressView(value: min(1.0, arSession.scanElapsed / arSession.maxScanDuration))
                .tint(.red)
                .frame(width: 220)

            Text("위→옆→반대편 순으로 천천히 이동하세요")
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))

            Button(action: { arSession.stopScan() }) {
                Label("스캔 종료", systemImage: "stop.circle.fill")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 220, height: 56)
                    .background(Color.gray.opacity(0.85))
                    .cornerRadius(28)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    // MARK: - Sub-views

    private var angleBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                let filled = arSession.pitchScore >= Float(i) * 0.1
                RoundedRectangle(cornerRadius: 2)
                    .fill(filled ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 18, height: CGFloat(6 + i * 3))
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var completeBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("스캔 완료!")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("\(capture.currentSessionFrameCount)개 프레임 저장됨")
                .foregroundColor(.white.opacity(0.85))
            Text("Files 앱 → 내 iPhone → ARCaptures")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(36)
        .background(.black.opacity(0.88))
        .cornerRadius(24)
    }

    // MARK: - Actions

    private func startScan() {
        let id = capture.startSession()
        currentSessionId = id
        currentSessionStart = Date()
        arSession.startScan()
    }
}
