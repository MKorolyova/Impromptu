//
//  NearbyFriendFinder.swift
//  Impromptu-app
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction

/// Who you are to the phones nearby: just enough to show the offer and add you as a friend.
nonisolated struct NearbyIdentity: Codable, Equatable, Sendable {
    let userId: UUID
    let firstName: String
    let lastName: String
    let nickname: String?

    /// What the app calls people (`Person.displayName`).
    var displayName: String { nickname ?? firstName }
}

/// Someone close by with Add Friend open.
struct NearbyPeer: Identifiable, Equatable {
    /// This visit's connection to them; a new one if they reopen the screen.
    let id: String
    let identity: NearbyIdentity
    /// Metres between the phones. Nil until measured, or when either phone can't measure it.
    var distance: Float?
}

enum NearbyFriendEvent: Equatable {
    /// Someone appeared, or their distance changed.
    case updated(NearbyPeer)
    case lost(peerId: String)
    /// They tapped Accept, or Add on you in the list.
    case accepted(peerId: String)
    case declined(peerId: String)
    /// The user turned down Nearby Interactions, so distances won't be measured.
    case distanceNotAllowed
    /// Phones found but not introduced yet (still connecting), so the screen can say so.
    case connecting(count: Int)
    /// iOS wouldn't let the app look for phones, e.g. Local Network access is off.
    case searchFailed(String)
}

/// Finds other phones with Add Friend open and introduces you, without the server: Multipeer
/// Connectivity (Bluetooth and peer-to-peer Wi-Fi) carries the messages, and Nearby Interaction
/// measures how far apart the phones are on iPhones with an Ultra Wideband chip. Works while the screen is open.
protocol NearbyFriendFinding: AnyObject {
    /// Whether this iPhone can measure the distance to another one (iPhone 11 or newer, not SE).
    var canMeasureDistance: Bool { get }
    var onEvent: ((NearbyFriendEvent) -> Void)? { get set }
    func start(as identity: NearbyIdentity)
    func stop()
    func accept(_ peerId: String)
    func decline(_ peerId: String)
}

/// What two phones say to each other.
nonisolated enum NearbyFriendMessage: Codable, Equatable {
    /// Sent once connected. `distanceToken` is an archived `NIDiscoveryToken`, nil when this phone can't measure.
    case hello(NearbyIdentity, distanceToken: Data?)
    case accept
    case decline
}

final class NearbyFriendFinder: NSObject, NearbyFriendFinding {
    /// Must match NSBonjourServices in Config/App-Info.plist (`_impromptu-add._tcp` and `._udp`).
    static let serviceType = "impromptu-add"
    private static let inviteTimeout: TimeInterval = 10
    /// How often phones that are found but not connected are invited (again).
    private static let retryInterval: Duration = .seconds(3)
    /// Normally only one of two phones invites; after this long without connecting, the other does too,
    /// in case the first can't see it (Multipeer sometimes only finds a phone one way).
    private static let inviteAnywayAfter: TimeInterval = 6

    var onEvent: ((NearbyFriendEvent) -> Void)?

    var canMeasureDistance: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    private struct Connection {
        let peerID: MCPeerID
        var peer: NearbyPeer?
        var distanceSession: NISession?
        /// Their token, kept until our distance session for them exists.
        var theirToken: NIDiscoveryToken?
        var isMeasuring = false
    }

    private var identity: NearbyIdentity?
    /// Random for each visit, so nothing about you is broadcast before two phones connect.
    private var myPeerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// By the other phone's peer name.
    private var connections: [String: Connection] = [:]
    /// Phones the browser can see, connected or not, and when each was first seen.
    private var discovered: [String: (peerID: MCPeerID, since: Date)] = [:]
    /// Invitations out or accepted, until they connect or fail.
    private var invitedAt: [String: Date] = [:]
    private var retryTask: Task<Void, Never>?
    private var reportedConnecting = 0

    func start(as identity: NearbyIdentity) {
        stop()
        self.identity = identity
        let peerID = MCPeerID(displayName: UUID().uuidString)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        myPeerID = peerID
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.retryInterval)
                self?.inviteWaitingPhones()
            }
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        connections.values.forEach { $0.distanceSession?.invalidate() }
        connections = [:]
        discovered = [:]
        invitedAt = [:]
        reportedConnecting = 0
        advertiser = nil
        browser = nil
        session = nil
        myPeerID = nil
        identity = nil
    }

    func accept(_ peerId: String) {
        send(.accept, to: peerId)
    }

    func decline(_ peerId: String) {
        send(.decline, to: peerId)
    }

    // MARK: Connections

    private func send(_ message: NearbyFriendMessage, to peerId: String) {
        guard let session, let peerID = connections[peerId]?.peerID,
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [peerID], with: .reliable)
    }

    private func connection(for peerID: MCPeerID) -> Connection {
        connections[peerID.displayName] ?? Connection(peerID: peerID)
    }

    private func found(_ peerID: MCPeerID) {
        if discovered[peerID.displayName] == nil { discovered[peerID.displayName] = (peerID, .now) }
        reportConnecting()
        if isFirstToInvite(peerID) { invite(peerID) }
    }

    private func lost(_ peerID: MCPeerID) {
        discovered[peerID.displayName] = nil
        reportConnecting()
    }

    /// When both phones see each other, only one invites, so they don't connect twice.
    private func isFirstToInvite(_ peerID: MCPeerID) -> Bool {
        guard let myPeerID else { return false }
        return myPeerID.displayName < peerID.displayName
    }

    private func isConnected(_ peerId: String) -> Bool {
        session?.connectedPeers.contains { $0.displayName == peerId } ?? false
    }

    private func isInviting(_ peerId: String) -> Bool {
        invitedAt[peerId].map { Date.now.timeIntervalSince($0) < Self.inviteTimeout + 2 } ?? false
    }

    private func invite(_ peerID: MCPeerID) {
        guard let session, let browser, !isConnected(peerID.displayName), !isInviting(peerID.displayName) else { return }
        invitedAt[peerID.displayName] = .now
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: Self.inviteTimeout)
    }

    /// Every few seconds: invite again anyone found but not connected, in case an invitation failed.
    private func inviteWaitingPhones() {
        for (peerId, entry) in discovered where !isConnected(peerId) {
            if isFirstToInvite(entry.peerID) || Date.now.timeIntervalSince(entry.since) > Self.inviteAnywayAfter {
                invite(entry.peerID)
            }
        }
    }

    private func acceptsInvitation(from peerID: MCPeerID) -> Bool {
        guard session != nil, !isConnected(peerID.displayName) else { return false }
        invitedAt[peerID.displayName] = .now
        return true
    }

    /// Phones found but not introduced yet, if the count changed.
    private func reportConnecting() {
        let count = discovered.keys.filter { connections[$0]?.peer == nil }.count
        guard count != reportedConnecting else { return }
        reportedConnecting = count
        onEvent?(.connecting(count: count))
    }

    private func searchFailed(_ error: Error) {
        let code = (error as NSError).code
        onEvent?(.searchFailed("iOS stopped Impromptu from looking for phones nearby (error \(code))."))
    }

    private func didConnect(_ peerID: MCPeerID) {
        invitedAt[peerID.displayName] = nil
        var connection = connection(for: peerID)
        if canMeasureDistance, connection.distanceSession == nil {
            let distanceSession = NISession()
            distanceSession.delegateQueue = .main
            distanceSession.delegate = self
            connection.distanceSession = distanceSession
        }
        connections[peerID.displayName] = connection
        measureIfReady(peerID.displayName)

        guard let identity else { return }
        let token = connection.distanceSession?.discoveryToken.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        send(.hello(identity, distanceToken: token), to: peerID.displayName)
    }

    /// Also when an invitation fails; the retry picks them up again while they're still found.
    private func didDisconnect(_ peerID: MCPeerID) {
        invitedAt[peerID.displayName] = nil
        defer { reportConnecting() }
        guard let connection = connections.removeValue(forKey: peerID.displayName) else { return }
        connection.distanceSession?.invalidate()
        if connection.peer != nil { onEvent?(.lost(peerId: peerID.displayName)) }
    }

    private func didReceive(_ data: Data, from peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NearbyFriendMessage.self, from: data) else { return }
        let peerId = peerID.displayName
        switch message {
        case .hello(let identity, let tokenData):
            var connection = connection(for: peerID)
            let peer = NearbyPeer(id: peerId, identity: identity, distance: connection.peer?.distance)
            connection.peer = peer
            connection.theirToken = tokenData.flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: $0)
            }
            connections[peerId] = connection
            measureIfReady(peerId)
            onEvent?(.updated(peer))
            reportConnecting()
        case .accept:
            onEvent?(.accepted(peerId: peerId))
        case .decline:
            onEvent?(.declined(peerId: peerId))
        }
    }

    /// Starts measuring once we have both our session for them and their token.
    private func measureIfReady(_ peerId: String) {
        guard var connection = connections[peerId], !connection.isMeasuring,
              let distanceSession = connection.distanceSession, let token = connection.theirToken else { return }
        distanceSession.run(NINearbyPeerConfiguration(peerToken: token))
        connection.isMeasuring = true
        connections[peerId] = connection
    }

    // MARK: Distance

    private func peerId(for distanceSession: NISession) -> String? {
        connections.first { $0.value.distanceSession === distanceSession }?.key
    }

    private func updateDistance(_ distance: Float?, in distanceSession: NISession) {
        guard let peerId = peerId(for: distanceSession), var peer = connections[peerId]?.peer else { return }
        peer.distance = distance
        connections[peerId]?.peer = peer
        onEvent?(.updated(peer))
    }

    private func distanceSessionEnded(_ distanceSession: NISession, error: Error) {
        guard let peerId = peerId(for: distanceSession) else { return }
        updateDistance(nil, in: distanceSession)
        connections[peerId]?.distanceSession = nil
        connections[peerId]?.isMeasuring = false
        if (error as? NIError)?.code == .userDidNotAllow { onEvent?(.distanceNotAllowed) }
    }
}

// MARK: - MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate
// Called on Multipeer's own queue, so each hops to the main queue in order.

extension NearbyFriendFinder: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch state {
                case .connected: self.didConnect(peerID)
                case .notConnected: self.didDisconnect(peerID)
                case .connecting: break
                @unknown default: break
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.didReceive(data, from: peerID) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                             fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // Turn down a second connection to a phone that's already connected.
                let accepts = self.acceptsInvitation(from: peerID)
                invitationHandler(accepts, accepts ? self.session : nil)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.searchFailed(error) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.found(peerID) }
        }
    }

    // Stops inviting them; a connected phone that leaves is handled when its session disconnects.
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.lost(peerID) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.searchFailed(error) }
        }
    }
}

// MARK: - NISessionDelegate
// `delegateQueue` is main, but hop explicitly like the Multipeer callbacks, in order.

extension NearbyFriendFinder: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let distance = nearbyObjects.first?.distance
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.updateDistance(distance, in: session) }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.updateDistance(nil, in: session)
                // Lost track for a moment; ask again with the same token.
                if reason == .timeout, let configuration = session.configuration { session.run(configuration) }
            }
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        DispatchQueue.main.async {
            if let configuration = session.configuration { session.run(configuration) }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.distanceSessionEnded(session, error: error) }
        }
    }
}
