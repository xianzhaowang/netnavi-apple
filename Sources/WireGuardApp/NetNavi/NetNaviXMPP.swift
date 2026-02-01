//
import Foundation
import XMPPFramework

#if os(iOS)
import UIKit
#endif

// =======================================================
// MARK: - XMPP Control Client (Single File, Hardened)
// =======================================================

public final class XMPPControlClient: NSObject {

    public static let shared = XMPPControlClient()

    private let stream = XMPPStream()
    private let reconnect = XMPPReconnect()
    private var streamManagement: XMPPStreamManagement!

    private var password: String = ""
    private var manualDisconnect = false

    // Router
    private var handlers: [String: Handler] = [:]

    public typealias Handler = (_ from: String,
                                _ payload: ControlPayload,
                                _ client: XMPPControlClient) -> Void

    // Background task (iOS)
    #if os(iOS)
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    // ===================================================
    // MARK: - Init
    // ===================================================

    override private init() {
        super.init()
        setup()
    }

    private func setup() {
        let q1 = DispatchQueue(label: "xmpp.control.stream")
        let q2 = DispatchQueue(label: "xmpp.control.sm")

        stream.addDelegate(self, delegateQueue: q1)
        reconnect.activate(stream)

        // ---- XEP-0198 Stream Management ----
        let storage = XMPPStreamManagementMemoryStorage()
        streamManagement = XMPPStreamManagement(storage: storage)
        streamManagement.autoResume = true
        streamManagement.ackResponseDelay = 0
        streamManagement.activate(stream)
        streamManagement.addDelegate(self, delegateQueue: q2)

        #if os(iOS)
        stream.enableBackgroundingOnSocket = true
        #endif
    }

    // ===================================================
    // MARK: - Public API
    // ===================================================

    public func start(jid: String,
                      password: String,
                      host: String,
                      port: UInt16 = 5222) {

        guard !stream.isConnected else { return }

        self.password = password
        self.manualDisconnect = false

        stream.myJID = XMPPJID(string: jid)
        stream.hostName = host
        stream.hostPort = port

        do {
            try stream.connect(withTimeout: XMPPStreamTimeoutNone)
            log("connecting to \(host)")
        } catch {
            log("connect error: \(error)")
        }
    }

    public func stop() {
        manualDisconnect = true
        goOffline()
        stream.disconnect()
    }

    public func send(to jid: String, text: String) {
        guard stream.isAuthenticated else { return }
        let msg = XMPPMessage(type: "chat", to: XMPPJID(string: jid))
        msg.addBody(text)
        stream.send(msg)
    }

    public func sendJSON(to jid: String, object: Any) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }

        send(to: jid, text: text)
    }

    // ===================================================
    // MARK: - Router
    // ===================================================

    public func on(_ command: String, handler: @escaping Handler) {
        handlers[command] = handler
    }

    private func route(from: String, body: String) {

        guard let envelope = ControlEnvelope.parse(body) else {
            log("invalid message format")
            return
        }

        guard verify(envelope: envelope) else {
            log("signature verification failed")
            return
        }

        handlers[envelope.cmd]?(from, envelope.payload, self)
    }

    // ===================================================
    // MARK: - Presence
    // ===================================================

    private func goOnline() {
        stream.send(XMPPPresence())
    }

    private func goOffline() {
        stream.send(XMPPPresence(type: "unavailable"))
    }
}

// =======================================================
// MARK: - Payload
// =======================================================

public enum ControlPayload {
    case text(String)
    case json([String: Any])

    public var json: [String: Any]? {
        if case .json(let j) = self { return j }
        return nil
    }
}

// =======================================================
// MARK: - Signed Envelope
// =======================================================

struct ControlEnvelope {

    let cmd: String
    let ts: TimeInterval
    let nonce: String
    let payload: ControlPayload
    let sig: String

    static func parse(_ raw: String) -> ControlEnvelope? {
        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cmd = json["cmd"] as? String,
            let ts = json["ts"] as? TimeInterval,
            let nonce = json["nonce"] as? String,
            let sig = json["sig"] as? String
        else { return nil }

        let payload: ControlPayload
        if let p = json["payload"] as? [String: Any] {
            payload = .json(p)
        } else if let p = json["payload"] as? String {
            payload = .text(p)
        } else {
            payload = .text("")
        }

        return ControlEnvelope(cmd: cmd, ts: ts, nonce: nonce, payload: payload, sig: sig)
    }
}

// =======================================================
// MARK: - Signature Verification
// =======================================================

extension XMPPControlClient {

    private func verify(envelope: ControlEnvelope) -> Bool {

        // ---- Replay window (example: 120s) ----
        if abs(Date().timeIntervalSince1970 - envelope.ts) > 120 {
            log("timestamp outside window")
            return false
        }

        // ---- HMAC verification ----
        let canonical = "\(envelope.cmd)|\(envelope.ts)|\(envelope.nonce)|\(canonicalPayload(envelope.payload))"
        let expected = HMAC.sha256(message: canonical, secret: ControlSecrets.sharedKey)

        return expected == envelope.sig
    }

    private func canonicalPayload(_ payload: ControlPayload) -> String {
        switch payload {
        case .text(let t):
            return t
        case .json(let j):
            let d = try? JSONSerialization.data(withJSONObject: j, options: [.sortedKeys])
            return String(data: d ?? Data(), encoding: .utf8) ?? ""
        }
    }
}

// =======================================================
// MARK: - XMPP Delegates
// =======================================================

extension XMPPControlClient: XMPPStreamDelegate {

    public func xmppStreamDidConnect(_ stream: XMPPStream) {
        log("connected, authenticating")
        try? stream.authenticate(withPassword: password)
    }

    public func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        log("authenticated")
        goOnline()
        #if os(iOS)
        beginBGTask()
        #endif
    }

    public func xmppStreamDidDisconnect(_ sender: XMPPStream, withError error: Error?) {
        log("disconnected: \(error?.localizedDescription ?? "clean")")
        #if os(iOS)
        endBGTask()
        #endif
    }

    public func xmppStream(_ sender: XMPPStream, didReceive message: XMPPMessage) {
        guard
            let body = message.body(forLanguage: ""),
            let from = message.from?.bare
        else { return }

        log("rx from \(from)")
        route(from: from, body: body)
    }
}

extension XMPPControlClient: XMPPStreamManagementDelegate {

    public func xmppStreamManagementDidEnable(_ sender: XMPPStreamManagement) {
        log("stream management enabled")
    }

    public func xmppStreamManagement(_ sender: XMPPStreamManagement, wasResumed resumed: Bool) {
        log("stream resumed: \(resumed)")
    }
}

// =======================================================
// MARK: - iOS Background
// =======================================================

#if os(iOS)
private extension XMPPControlClient {

    func beginBGTask() {
        if bgTask == .invalid {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "xmpp-control") {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
            log("background task started")
        }
    }

    func endBGTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
            log("background task ended")
        }
    }
}
#endif

// =======================================================
// MARK: - HMAC (Crypto)
// =======================================================

import CryptoKit

enum HMAC {
    static func sha256(message: String, secret: String) -> String {
        let key = SymmetricKey(data: secret.data(using: .utf8)!)
        let sig = CryptoKit.HMAC<SHA256>.authenticationCode(
            for: message.data(using: .utf8)!,
            using: key
        )
        return Data(sig).base64EncodedString()
    }
}

// =======================================================
// MARK: - Secrets
// =======================================================

enum ControlSecrets {
    // 🔐 Replace with Secure Enclave / Keychain
    static let sharedKey = "REPLACE_WITH_256BIT_SECRET"
}

// =======================================================
// MARK: - Logging
// =======================================================

private extension XMPPControlClient {
    func log(_ msg: String) {
        print("[XMPP-Control] \(msg)")
    }
}

