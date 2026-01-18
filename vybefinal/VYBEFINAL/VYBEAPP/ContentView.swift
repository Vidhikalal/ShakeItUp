import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var detector = BeatDetector()
    @StateObject private var webStore = VybeWebViewStore()

    private let lovableURL = URL(string: "https://vybe2.lovable.app")!

    var body: some View {
        VybeLovableWebView(
            url: lovableURL,
            store: webStore,
            onMessage: { body in
                handleWebMessage(body)
            },
            onLoaded: {
                onWebLoaded()
            }
        )
        .ignoresSafeArea()
        .onAppear {
            // sanity test pulse to confirm haptics
            detector.fireHaptics(intensity: 1.0)
        }
        .onReceive(detector.$volume) { _ in pushStateToWeb() }
        .onReceive(detector.$isBeat) { _ in pushStateToWeb() }
        .onReceive(detector.$sensitivity) { _ in pushStateToWeb() }
        .onReceive(detector.$output) { _ in pushStateToWeb() }
    }

    private func onWebLoaded() {
        // Re-assert audio/haptics after WKWebView load
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowAirPlay])
            if #available(iOS 13.0, *) {
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }
            try session.setActive(true)
            print("✅ Audio session active after WebView load")
        } catch {
            print("❌ Audio session error after WebView load:", error)
        }

        webStore.sendToWeb(["type": "nativeReady"])
        pushStateToWeb()
    }

    private func pushStateToWeb() {
        webStore.sendToWeb([
            "type": "beatState",
            "isBeat": detector.isBeat,
            "volume": detector.volume,
            "sensitivity": detector.sensitivity,
            "output": detector.output.rawValue,
            "watchReachable": WatchHapticsSender.shared.isWatchReachable
        ])
    }

    private func handleWebMessage(_ body: Any) {
        // Accept dict or JSON string
        let dict: [String: Any]?

        if let d = body as? [String: Any] {
            dict = d
        } else if let s = body as? String,
                  let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = obj
        } else {
            dict = nil
        }

        guard let dict, let type = dict["type"] as? String else {
            print("⚠️ Unknown message:", body)
            return
        }

        switch type {
        case "start":
            detector.start()
            webStore.sendToWeb(["type": "started"])

        case "stop":
            detector.stop()
            webStore.sendToWeb(["type": "stopped"])

        case "forcePulse":
            detector.fireHaptics(intensity: 1.0)

        case "setSensitivity":
            if let v = dict["value"] as? Double {
                detector.sensitivity = Float(v)
            } else if let v = dict["value"] as? Float {
                detector.sensitivity = v
            } else if let v = dict["value"] as? Int {
                detector.sensitivity = Float(v)
            }

        case "setOutput":
            if let s = dict["value"] as? String,
               let out = HapticOutput(rawValue: s) {
                detector.output = out
                webStore.sendToWeb(["type": "outputSet", "value": out.rawValue])
            }

        default:
            print("⚠️ Unhandled type:", type, dict)
        }
    }
}
