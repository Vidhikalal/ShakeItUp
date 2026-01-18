import Foundation
import WatchConnectivity
import WatchKit

final class WatchHapticsReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchHapticsReceiver()

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

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }

    private func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        guard type == "vibrate" else { return }

        let style = (message["style"] as? String) ?? "click"

        DispatchQueue.main.async {
            switch style {
            case "notification":
                WKInterfaceDevice.current().play(.notification)
            case "failure":
                WKInterfaceDevice.current().play(.failure)
            case "success":
                WKInterfaceDevice.current().play(.success)
            default:
                WKInterfaceDevice.current().play(.click)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
