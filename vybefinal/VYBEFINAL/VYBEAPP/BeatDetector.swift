import Foundation
import AVFoundation
import CoreHaptics
import Combine
import AudioToolbox
import WatchConnectivity

// MARK: - Watch sender (iOS side)
final class WatchHapticsSender: NSObject, WCSessionDelegate {
    static let shared = WatchHapticsSender()

    private override init() {
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Watch is reachable only when watch app is active/foreground.
    var isWatchReachable: Bool {
        WCSession.default.isReachable
    }

    func vibrate(style: String = "click") {
        let session = WCSession.default
        guard session.isReachable else { return }
        session.sendMessage(["type": "vibrate", "style": style], replyHandler: nil, errorHandler: nil)
    }

    // WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}

// MARK: - BeatDetector
final class BeatDetector: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var hapticEngine: CHHapticEngine?

    @Published var isBeat: Bool = false
    @Published var volume: Float = 0.0
    @Published var sensitivity: Float = 1.3

    // ✅ user choice: phone / watch / both
    @Published var output: HapticOutput = .phone

    private var volumeHistory: [Float] = []
    private let historyLimit = 10

    init() {
        prepareHaptics()
        _ = WatchHapticsSender.shared
    }

    func start() {
        setupAudio()
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio Session Deactivation Error: \(error)")
        }

        print("🛑 Audio Engine Stopped")
    }

    private func setupAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowAirPlay]
            )

            if #available(iOS 13.0, *) {
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }

            try session.setActive(true)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.analyzeBuffer(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            print("✅ Audio Engine Started")
        } catch {
            print("❌ Audio Engine Error: \(error)")
        }
    }

    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let ptr = UnsafeBufferPointer(start: channelData, count: frameCount)

        let sum = ptr.reduce(0) { $0 + ($1 * $1) }
        let rms = sqrt(sum / Float(frameCount))

        DispatchQueue.main.async {
            self.volume = rms
            let avg = self.volumeHistory.reduce(0, +) / Float(max(1, self.volumeHistory.count))

            // "lower" = catch quieter beats
            let floor: Float = 0.0025

            if rms > (avg * self.sensitivity) && rms > floor {
                if !self.isBeat {
                    // ✅ route to phone/watch/both
                    self.fireHaptics(intensity: rms)

                    self.isBeat = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.isBeat = false
                    }
                }
            }

            self.volumeHistory.append(rms)
            if self.volumeHistory.count > self.historyLimit {
                self.volumeHistory.removeFirst()
            }
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try hapticEngine?.start()
        } catch {
            print("❌ Haptic Engine Failed: \(error)")
        }
    }

    /// ✅ Single entry-point for haptics based on user choice
    func fireHaptics(intensity: Float) {
        switch output {
        case .phone:
            triggerBeatHaptic(intensity: intensity)

        case .watch:
            // Watch haptics are pattern-based (no custom intensity). "click" feels crisp.
            WatchHapticsSender.shared.vibrate(style: "click")

        case .both:
            triggerBeatHaptic(intensity: intensity)
            WatchHapticsSender.shared.vibrate(style: "click")
        }
    }

    /// Stronger + lower (bassy) iPhone haptic
    func triggerBeatHaptic(intensity: Float) {
        AudioServicesPlaySystemSound(1352)

        guard let engine = hapticEngine else { return }
        try? engine.start()

        // Stronger
        let strength = min(max(intensity * 25.0, 0.9), 1.0)
        // Lower (less sharp)
        let sharpness: Float = 0.15
        // Longer rumble
        let mainDuration: Double = 0.28

        let main = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: mainDuration
        )

        // tail rumble for “heavier” feel
        let tail = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(strength, 0.95)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.10)
            ],
            relativeTime: 0.10,
            duration: 0.22
        )

        do {
            let pattern = try CHHapticPattern(events: [main, tail], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("❌ Haptic Pattern Error: \(error)")
        }
    }
}
