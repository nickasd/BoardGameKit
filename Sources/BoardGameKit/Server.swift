@preconcurrency import GameKit
import BoardGameKitHost

@MainActor var ServerShared: Server!

final class LocalServer: Server {
    
    weak var delegate: (any ServerDelegate)?
    
    func connect() {
    }
    
    func disconnect() {
    }
    
    func send<T>(_ data: T) where T : Request {
        GameHostShared.receive(RequestCoder.encode(RawRequest(data)), from: .local!)
    }
    
}

extension Server {
    
    func receive(_ data: Data) {
        do {
            let data = try RequestCoder.decode(RawRequest.self, from: data)
            Logger.shared.info("Client received message: \(data.prettyPrinted)")
            if data.name == ErrorResponse.name {
                throw HostError(message: try RequestCoder.decode(ErrorResponse.self, from: data.data).data)
            }
            delegate?.server(self, didReceiveRequest: data)
        } catch {
            delegate?.server(self, handleError: error)
        }
    }
    
}

final class WebsocketServer: NSObject, Server, URLSessionWebSocketDelegate {
    
    public enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }
    
    let url: URL
    weak var delegate: (any ServerDelegate)?
    public private(set) var connectionStatus = ConnectionStatus.disconnected
    
    private var urlSession: URLSession?
    private var websocketTask: URLSessionWebSocketTask?
//    private var pingTimer: Timer?
    
    init(url: URL) {
        self.url = url
    }
    
    public func connect() {
        if connectionStatus != .disconnected {
            return
        }
        connectionStatus = .connecting
        let request = URLRequest(url: url)
        let urlSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.urlSession = urlSession
        let websocketTask = urlSession.webSocketTask(with: request)
        self.websocketTask = websocketTask
        websocketTask.resume()
//        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
//            self.websocketTask?.sendPing(pongReceiveHandler: { error in }) // NWProtocolWebSocket.Options.autoReplyPing has no effect (FB9883768)
//        }
    }
    
    public func disconnect() {
        if connectionStatus == .disconnected {
            return
        }
        connectionStatus = .disconnected
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
//        pingTimer?.invalidate()
//        pingTimer = nil
    }
    
    private func receive() {
        websocketTask?.receive { [self] result in
            Task { @MainActor in
                if websocketTask?.state != .running {
                    return
                }
                switch result {
                case .failure(let error):
                    Logger.shared.error(error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .data(let data):
                        receive(data)
                    default:
                        fatalError()
                    }
                }
                receive()
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            connectionStatus = .connected
            Logger.shared.info("Client connected")
            delegate?.serverDidConnect(self)
            receive()
        }
    }

    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            Logger.shared.info("Client disconnected: \(closeCode)")
            if closeCode != .goingAway {
                delegate?.serverDidDisconnect(self)
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if task != websocketTask {
                return
            }
            Logger.shared.info("Client disconnected: \(error?.localizedDescription ?? "nil")")
            delegate?.serverDidDisconnect(self)
        }
    }

    nonisolated public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task { @MainActor in
            Logger.shared.info("Client disconnected: \(error?.localizedDescription ?? "nil")")
            delegate?.serverDidDisconnect(self)
        }
    }

    public func send<T: Request>(_ data: T) {
        Task {
            let data = RawRequest(data)
            Logger.shared.info("Client will send message: \(data.prettyPrinted)")
            do {
                try await websocketTask!.send(.data(RequestCoder.encode(data)))
            } catch {
                delegate?.server(self, handleError: error)
            }
        }
    }

}

final class GameCenterServer: NSObject, Server, GKMatchDelegate {
    
//    static var disconnectedServer: GameCenterServer?
    
    let match: GKMatch
    let host: GKPlayer
    weak var delegate: (any ServerDelegate)?
    
    init(match: GKMatch, host: GKPlayer) {
        self.match = match
        self.host = host
        super.init()
        match.delegate = self
    }
    
    public func connect() {
    }

    public func disconnect() {
        match.delegate = nil
        match.disconnect()
    }
    
    func send<T>(_ data: T) where T : Request {
        if host == GKLocalPlayer.local {
            GameHostShared.receive(RequestCoder.encode(RawRequest(data)), from: .local!)
        } else {
            do {
                try match.send(RequestCoder.encode(RawRequest(data)), to: [host], dataMode: .reliable)
            } catch {
                delegate?.server(self, handleError: error)
            }
        }
    }
    
    nonisolated public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor in
            if let GameHostShared = GameHostShared as? GameCenterGameHost, let user = GameHostShared.user(for: player) {
                GameHostShared.receive(data, from: user)
            } else {
                receive(data)
            }
        }
    }
    
    nonisolated public func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in
            Logger.shared.info("Match failed: \(error?.localizedDescription ?? "nil")")
            delegate?.serverDidDisconnect(self)
        }
    }
    
    nonisolated public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            Logger.shared.info("\(player.displayName) did change state to \(state.rawValue)")
            if let host = GameHostShared as? GameCenterGameHost {
                switch state {
                case .connected:
                    host.reconnectUser(for: player)
                case .disconnected, .unknown:
                    guard let user = host.user(for: player) else {
                        return
                    }
                    host.removeUser(user)
                    if Scene2D.current.serverShouldReinvitePlayer(self) {
//                        let matchRequest = GKMatchRequest() // No way to join GKMatch after accepting GKInvite (FB15864883)
//                        matchRequest.recipients = [player]
//                        matchRequest.recipientResponseHandler = { player, response in
//                            Logger.shared.info("Invited player \(player.displayName) responsed \(response)")
//                        }
//                        do {
//                            try await GKMatchmaker.shared().addPlayers(to: match, matchRequest: matchRequest)
//                            Logger.shared.info("Sent invitation to \(player.displayName)")
//                        } catch {
//                            Logger.shared.error("Invitation to \(player.displayName) failed.\n\(error.localizedDescription)")
//                        }
                    }
                    @unknown default:
                    break
                }
            } else {
                switch state {
                case .connected:
                    break
                case .disconnected, .unknown:
                    delegate?.serverDidDisconnect(self)
                @unknown default:
                    break
                }
            }
        }
    }
    
    nonisolated func match(_ match: GKMatch, shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        return false // returning true only works for two-player matches, so make all matches behave the same. GKMatchDelegate.match(_:shouldReinviteDisconnectedPlayer:) should work for any number of players (FB22525795)
    }
    
}
