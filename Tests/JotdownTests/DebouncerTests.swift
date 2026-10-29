import Testing
import Foundation
@testable import Jotdown

final class ManualScheduler: DebounceScheduler {
    final class Item: DebounceCancellable {
        var due: TimeInterval; var action: () -> Void; var cancelled = false
        init(due: TimeInterval, action: @escaping () -> Void) { self.due = due; self.action = action }
        func cancel() { cancelled = true }
    }
    var now: TimeInterval = 0
    var items: [Item] = []
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DebounceCancellable {
        let i = Item(due: now + delay, action: action); items.append(i); return i
    }
    func advance(_ dt: TimeInterval) {
        now += dt
        for i in items where !i.cancelled && i.due <= now { i.cancelled = true; i.action() }
    }
}

@Suite struct DebouncerTests {
    @Test func rapidTriggersFireOnce() {
        let s = ManualScheduler(); var n = 0
        let d = Debouncer(delay: 1.0, scheduler: s) { n += 1 }
        for _ in 0..<10 { d.trigger(); s.advance(0.3) }
        #expect(n == 0)
        s.advance(1.0)
        #expect(n == 1)
        #expect(!d.isPending)
    }

    @Test func firesAfterDelayExactly() {
        let s = ManualScheduler(); var n = 0
        let d = Debouncer(delay: 1.0, scheduler: s) { n += 1 }
        d.trigger(); s.advance(0.99); #expect(n == 0)
        s.advance(0.01); #expect(n == 1)
    }

    @Test func flushRunsImmediatelyOnce() {
        let s = ManualScheduler(); var n = 0
        let d = Debouncer(delay: 1.0, scheduler: s) { n += 1 }
        d.flush(); #expect(n == 0)          // ไม่มีงานค้าง
        d.trigger(); d.flush(); #expect(n == 1)
        s.advance(5); #expect(n == 1)
    }

    @Test func cancelDropsPending() {
        let s = ManualScheduler(); var n = 0
        let d = Debouncer(delay: 1.0, scheduler: s) { n += 1 }
        d.trigger(); d.cancel(); s.advance(5)
        #expect(n == 0)
        #expect(!d.isPending)
    }
}
