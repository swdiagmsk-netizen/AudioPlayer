import XCTest
@testable import AudioPlayer

/// Предсказуемый генератор случайных чисел для тестов.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class QueueTests: XCTestCase {

    private func makeIDs(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    func testFisherYatesKeepsAllElements() {
        var generator = SeededGenerator(state: 1)
        let items = Array(0..<50)
        let shuffled = FisherYates.shuffled(items, using: &generator)
        XCTAssertEqual(shuffled.sorted(), items)
        XCTAssertNotEqual(shuffled, items)
    }

    func testMovedMatchesListBehaviour() {
        let items = ["a", "b", "c", "d"]
        XCTAssertEqual(FisherYates.moved(items, fromOffsets: IndexSet(integer: 0), toOffset: 3), ["b", "c", "a", "d"])
        XCTAssertEqual(FisherYates.moved(items, fromOffsets: IndexSet(integer: 3), toOffset: 0), ["d", "a", "b", "c"])
    }

    func testSequentialAdvanceStopsAtEnd() {
        let ids = makeIDs(3)
        var queue = PlaybackQueue()
        queue.set(items: ids, current: ids[0])
        XCTAssertEqual(queue.advance(auto: true), ids[1])
        XCTAssertEqual(queue.advance(auto: true), ids[2])
        XCTAssertNil(queue.advance(auto: true))
    }

    func testRepeatAllWraps() {
        let ids = makeIDs(2)
        var queue = PlaybackQueue()
        queue.repeatMode = .all
        queue.set(items: ids, current: ids[1])
        XCTAssertEqual(queue.advance(auto: true), ids[0])
    }

    func testRepeatOneReplaysOnAutoButSwitchesOnManual() {
        let ids = makeIDs(3)
        var queue = PlaybackQueue()
        queue.repeatMode = .one
        queue.set(items: ids, current: ids[0])
        XCTAssertEqual(queue.advance(auto: true), ids[0])
        XCTAssertEqual(queue.advance(auto: false), ids[1])
    }

    func testTrueShufflePlaysEveryTrackOncePerCycle() {
        var generator = SeededGenerator(state: 42)
        let ids = makeIDs(20)
        var queue = PlaybackQueue()
        queue.set(items: ids, current: ids[5], using: &generator)
        queue.setShuffle(true, using: &generator)
        var played: [UUID] = [ids[5]]
        while let next = queue.advance(auto: true, using: &generator) {
            played.append(next)
        }
        XCTAssertEqual(played.count, ids.count)
        XCTAssertEqual(Set(played), Set(ids))
        XCTAssertEqual(played.first, ids[5])
    }

    func testTrueShuffleNewCycleDoesNotStartWithLastTrack() {
        var generator = SeededGenerator(state: 7)
        let ids = makeIDs(6)
        var queue = PlaybackQueue()
        queue.repeatMode = .all
        queue.set(items: ids, current: ids[0], using: &generator)
        queue.setShuffle(true, using: &generator)
        for _ in 0..<50 {
            var last = queue.currentUID
            for _ in 0..<(ids.count - 1) {
                last = queue.advance(auto: true, using: &generator)
            }
            let firstOfNextCycle = queue.advance(auto: true, using: &generator)
            XCTAssertNotNil(firstOfNextCycle)
            XCTAssertNotEqual(firstOfNextCycle, last)
        }
    }

    func testShufflePreviousFollowsHistory() {
        var generator = SeededGenerator(state: 3)
        let ids = makeIDs(8)
        var queue = PlaybackQueue()
        queue.set(items: ids, current: ids[2], using: &generator)
        queue.setShuffle(true, using: &generator)
        let second = queue.advance(auto: false, using: &generator)
        _ = queue.advance(auto: false, using: &generator)
        XCTAssertEqual(queue.goBack(), second)
        XCTAssertEqual(queue.goBack(), ids[2])
        XCTAssertNil(queue.goBack())
    }

    func testShuffleSyncAddsAndRemoves() {
        var generator = SeededGenerator(state: 11)
        var ids = makeIDs(5)
        var queue = PlaybackQueue()
        queue.set(items: ids, current: ids[0], using: &generator)
        queue.setShuffle(true, using: &generator)
        _ = queue.advance(auto: true, using: &generator)
        let alreadyPlayed: Set<UUID> = [ids[0], queue.currentUID ?? ids[0]]
        let removed = ids.first { !alreadyPlayed.contains($0) }
        ids.removeAll { $0 == removed }
        let added = UUID()
        ids.append(added)
        queue.updateItems(ids, using: &generator)
        var rest: [UUID] = []
        while let next = queue.advance(auto: true, using: &generator) {
            rest.append(next)
        }
        XCTAssertTrue(rest.contains(added))
        if let removed {
            XCTAssertFalse(rest.contains(removed))
        }
        XCTAssertEqual(Set(rest).count, rest.count)
        XCTAssertTrue(alreadyPlayed.isDisjoint(with: rest))
    }
}
