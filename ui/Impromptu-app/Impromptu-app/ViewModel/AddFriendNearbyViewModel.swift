//
//  AddFriendNearbyViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// Add Friend → Nearby: two people open it and hold the tops of their phones together, then each
/// accepts on their own phone. Phones that can't measure distance pick each other from a list instead.
@Observable
final class AddFriendNearbyViewModel {
    enum Phase: Equatable {
        case looking
        /// "Become friends with Ada?": the phones touched, or they asked first.
        case offer(NearbyPeer)
        /// You accepted; waiting for them to.
        case waiting(NearbyPeer)
        case adding(NearbyPeer)
        case friends(Friend)
        /// They said not now, or walked away. Goes back to looking shortly.
        case ended(String)
        case failed(NearbyPeer, String)
    }

    /// Phones closer than this, in metres, count as touching.
    static let touchDistance: Float = 0.15
    /// Becoming friends this way shares both, as two people agreeing face to face.
    static let access = FriendAccess(canSeeLocation: true, canSeeNotes: true)

    private(set) var phase: Phase = .looking
    /// Everyone nearby with the screen open, closest first.
    private(set) var peers: [NearbyPeer] = []
    /// False once the user turns down Nearby Interactions; then it's the list, like on older iPhones.
    private(set) var isDistanceAllowed = true
    /// Phones found but still connecting, so the list can say something's happening.
    private(set) var connectingCount = 0
    /// Why iOS won't let the app look for phones at all.
    private(set) var searchError: String?
    let canMeasureDistance: Bool

    /// People who accepted you, ready for when you accept them.
    private var acceptedByThem: Set<String> = []
    /// Said no, either way, or already added; not offered again while the screen is open.
    private var passed: Set<String> = []

    private let user: User
    private let services: Services
    private let finder: NearbyFriendFinding

    init(user: User, services: Services) {
        self.user = user
        self.services = services
        finder = services.nearbyFriends
        canMeasureDistance = finder.canMeasureDistance
    }

    /// Whether to tell people to hold their phones together, or to pick from the list.
    var usesTouch: Bool {
        canMeasureDistance && isDistanceAllowed
    }

    func start() {
        finder.onEvent = { [weak self] event in self?.handle(event) }
        finder.start(as: NearbyIdentity(userId: user.id, firstName: user.firstName, lastName: user.lastName,
                                        nickname: user.nickname))
    }

    func stop() {
        finder.stop()
        finder.onEvent = nil
    }

    func handle(_ event: NearbyFriendEvent) {
        switch event {
        case .updated(let peer):
            upsert(peer)
            if phase == .looking, isTouching(peer) { phase = .offer(peer) }
        case .lost(let peerId):
            peers.removeAll { $0.id == peerId }
            acceptedByThem.remove(peerId)
            if let peer = phasePeer, peer.id == peerId, isAwaitingAnswer {
                phase = .ended("\(peer.identity.displayName) closed Add Friend.")
            }
        case .accepted(let peerId):
            acceptedByThem.insert(peerId)
            guard let peer = peers.first(where: { $0.id == peerId }) else { return }
            switch phase {
            case .waiting(let waitingFor) where waitingFor.id == peerId:
                Task { await addFriend(peer) }
            case .looking where !passed.contains(peerId):
                // They asked first, e.g. from the list.
                phase = .offer(peer)
            default:
                break
            }
        case .declined(let peerId):
            passed.insert(peerId)
            acceptedByThem.remove(peerId)
            if let peer = phasePeer, peer.id == peerId, isAwaitingAnswer {
                phase = .ended("\(peer.identity.displayName) said not now.")
            }
        case .distanceNotAllowed:
            isDistanceAllowed = false
        case .connecting(let count):
            connectingCount = count
        case .searchFailed(let message):
            searchError = message
        }
    }

    func accept() async {
        guard case .offer(let peer) = phase else { return }
        await say(yesTo: peer)
    }

    /// From the list: asks them, and they see the offer.
    func request(_ peer: NearbyPeer) async {
        guard phase == .looking else { return }
        await say(yesTo: peer)
    }

    /// "Not now" on an offer, or cancelling while waiting.
    func decline() {
        guard let peer = phasePeer, isAwaitingAnswer else { return }
        finder.decline(peer.id)
        passed.insert(peer.id)
        phase = .looking
    }

    func retry() async {
        guard case .failed(let peer, _) = phase else { return }
        await addFriend(peer)
    }

    /// Back to looking, e.g. to add someone else.
    func lookAgain() {
        phase = .looking
        if let touching = peers.first(where: isTouching) { phase = .offer(touching) }
    }

    // MARK: Private

    private var phasePeer: NearbyPeer? {
        switch phase {
        case .offer(let peer), .waiting(let peer), .adding(let peer), .failed(let peer, _): peer
        case .looking, .friends, .ended: nil
        }
    }

    private var isAwaitingAnswer: Bool {
        switch phase {
        case .offer, .waiting: true
        default: false
        }
    }

    private func isTouching(_ peer: NearbyPeer) -> Bool {
        !passed.contains(peer.id) && (peer.distance ?? .infinity) < Self.touchDistance
    }

    private func say(yesTo peer: NearbyPeer) async {
        finder.accept(peer.id)
        if acceptedByThem.contains(peer.id) {
            await addFriend(peer)
        } else {
            phase = .waiting(peer)
        }
    }

    private func addFriend(_ peer: NearbyPeer) async {
        phase = .adding(peer)
        do {
            let friend = try await services.friends.addFriend(peer.identity.userId, access: Self.access, for: user.id)
            passed.insert(peer.id)
            phase = .friends(friend)
        } catch {
            phase = .failed(peer, error.localizedDescription)
        }
    }

    private func upsert(_ peer: NearbyPeer) {
        if let index = peers.firstIndex(where: { $0.id == peer.id }) {
            peers[index] = peer
        } else {
            peers.append(peer)
        }
        peers.sort { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}
