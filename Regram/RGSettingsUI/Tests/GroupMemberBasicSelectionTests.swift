import Foundation

class Peer { let id: Int; init(_ id: Int) { self.id = id } }
final class TelegramUser: Peer { var botInfo: Int? = nil }
struct Account { let peerId = 1 }
struct Context { let account = Account() }
enum Mode { case ban, select }
enum Filter { case exclude([Int]), disable([Int]), excludeNonMembers, excludeBots }
func selectable(_ mode: Mode, _ filters: [Filter]) -> [(id: Int, enabled: Bool)] {
    let context = Context()
    let peers: [Peer] = [TelegramUser(1), TelegramUser(2), TelegramUser(3)]
    var results: [(Int, Bool)] = []
    membersLoop: for peer in peers {
        var enabled = true
        switch mode {
PRODUCTION_FILTER
        }
        results.append((peer.id, enabled))
    }
    return results
}
@main enum Checks {
    static func main() {
        precondition(selectable(.select, [.exclude([2])]).map(\.id) == [3], "Basic-group selection must exclude already-selected members from the outer list")
        precondition(selectable(.select, [.exclude([2, 3])]).isEmpty, "A fully-selected basic group must not offer duplicate member additions")
        precondition(selectable(.select, [.disable([2])]).first(where: { $0.id == 2 })?.enabled == false, "The existing disabled-row behavior must stay intact")
        print("Basic-group member selection passed: self, duplicate exclusions and disabled rows")
    }
}
