import Foundation

private func order(_ timestamp: Int32, peer: Int64 = 1, id: Int32 = 1) -> RGCommonMessageOrder {
    .init(timestamp: timestamp, peerId: peer, namespace: 0, messageId: id)
}
@main enum Tests {
    static func main() {
        let fresh = (1...8).map { RGCommonGroupSearchStatus(peerId: Int64($0)) }
        assert(RGCommonGroupSearchPolicy.nextGroups(fresh, orders: [], visibleLimit: 50, selectedGroup: nil) == [1, 2, 3])
        var limited = fresh; limited[0].loading = true; limited[1].loading = true
        assert(RGCommonGroupSearchPolicy.nextGroups(limited, orders: [], visibleLimit: 50, selectedGroup: nil) == [3])
        limited[2].loading = true
        assert(RGCommonGroupSearchPolicy.nextGroups(limited, orders: [], visibleLimit: 50, selectedGroup: nil).isEmpty)
        let visible = (90...139).map { order(Int32($0)) }
        var hot = RGCommonGroupSearchStatus(peerId: 1); hot.loaded = true; hot.oldest = order(100)
        var quiet = RGCommonGroupSearchStatus(peerId: 2); quiet.loaded = true; quiet.oldest = order(70)
        var done = RGCommonGroupSearchStatus(peerId: 3); done.loaded = true; done.hasMore = false
        assert(RGCommonGroupSearchPolicy.nextGroups([hot, quiet, done], orders: visible, visibleLimit: 50, selectedGroup: nil) == [1], "Fetch the busy group's tail before the global cutoff; do not skip unseen newer messages")
        hot.oldest = order(80)
        assert(RGCommonGroupSearchPolicy.nextGroups([hot, quiet, done], orders: visible, visibleLimit: 50, selectedGroup: nil).isEmpty)
        assert(RGCommonGroupSearchPolicy.nextGroups([hot, quiet, done], orders: visible, visibleLimit: 100, selectedGroup: nil) == [1, 2])
        hot.failed = true
        assert(RGCommonGroupSearchPolicy.nextGroups([hot, quiet], orders: [], visibleLimit: 50, selectedGroup: nil) == [2], "Failed requests wait for explicit retry")
        assert(RGCommonGroupSearchPolicy.nextGroups(fresh, orders: [], visibleLimit: 50, selectedGroup: 6) == [6])
        assert(RGCommonGroupSearchPolicy.nextGroups(fresh, orders: visible, visibleLimit: 0, selectedGroup: 6) == [6])
        assert(Set([order(10), order(10, peer: 2), order(10, id: 2)]).count == 3)
        assert(RGCommonGroupPreview.text("public secret", spoilers: [7..<13], reveal: false) == "public ▪▪▪▪▪▪")
        assert(RGCommonGroupPreview.text("public secret", spoilers: [7..<13], reveal: true) == "public secret")
        assert(RGCommonGroupPreview.text("A😀秘密", spoilers: [1..<4], reveal: false) == "A▪▪▪密")
        assert(RGCommonGroupPreview.text(String(repeating: "a", count: 1000), spoilers: [590..<1000], reveal: false).count == 600)
        assert(RGCommonGroupPreview.text("abc", spoilers: [-3..<1, 9..<10], reveal: false) == "▪bc")
        // Compare paginated merges against the complete server dataset, including skewed groups.
        var seed: UInt64 = 2818
        func random(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(upper))
        }
        for _ in 0..<20 {
            let server: [[RGCommonMessageOrder]] = (1...18).map { group in
                (0..<random(300)).map { message in order(Int32(random(100_000)), peer: Int64(group), id: Int32(message)) }.sorted(by: >)
            }
            var states = (1...18).map { RGCommonGroupSearchStatus(peerId: Int64($0)) }
            var loaded: [Int64: [RGCommonMessageOrder]] = [:]
            for (limit, selected) in [(50, Optional<Int64>.none), (100, nil), (250, nil), (50, 7), (150, 7)] {
                var requests = 0
                while true {
                    let known = loaded.filter { selected == nil || $0.key == selected }.values.flatMap { $0 }
                    let next = RGCommonGroupSearchPolicy.nextGroups(states, orders: known, visibleLimit: limit, selectedGroup: selected)
                    if next.isEmpty { break }
                    for id in next {
                        let index = Int(id) - 1
                        let count = min(server[index].count, (loaded[id]?.count ?? 0) + RGCommonGroupSearchPolicy.pageSize)
                        loaded[id] = Array(server[index].prefix(count))
                        states[index].loaded = true
                        states[index].hasMore = count < server[index].count
                        states[index].oldest = loaded[id]?.last
                        requests += 1
                    }
                    assert(requests < 500, "Pagination must converge")
                }
                let expected = server.enumerated().filter { selected == nil || Int64($0.offset + 1) == selected }.flatMap(\.element).sorted(by: >).prefix(limit)
                let actual = loaded.filter { selected == nil || $0.key == selected }.values.flatMap { $0 }.sorted(by: >).prefix(limit)
                assert(Array(actual) == Array(expected), "A globally merged page must match the complete history prefix")
            }
        }
        print("Common-group pagination passed: concurrency, busy-group cutoff, loaded-window expansion, filtering, failures, stable identity and spoiler previews.")
    }
}
