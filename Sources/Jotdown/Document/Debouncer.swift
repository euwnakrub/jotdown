import Foundation

protocol DebounceCancellable { func cancel() }

/// ตัวจัดเวลาที่ฉีดเข้าไปได้ (ของจริงใช้ main queue, เทสต์ใช้เวลาจำลอง)
protocol DebounceScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DebounceCancellable
}

struct MainQueueScheduler: DebounceScheduler {
    private final class Token: DebounceCancellable {
        let item: DispatchWorkItem
        init(_ i: DispatchWorkItem) { item = i }
        func cancel() { item.cancel() }
    }
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DebounceCancellable {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return Token(item)
    }
}

/// รอ `delay` วินาทีหลังการ trigger ครั้งสุดท้าย แล้วรัน action ครั้งเดียว
final class Debouncer {
    let delay: TimeInterval
    private let scheduler: DebounceScheduler
    private let action: () -> Void
    private var pending: DebounceCancellable?

    init(delay: TimeInterval, scheduler: DebounceScheduler = MainQueueScheduler(), action: @escaping () -> Void) {
        self.delay = delay; self.scheduler = scheduler; self.action = action
    }

    var isPending: Bool { pending != nil }

    func trigger() {
        pending?.cancel()
        pending = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.action()
        }
    }

    /// รัน action ทันทีถ้ามีงานค้าง
    func flush() {
        guard pending != nil else { return }
        cancel()
        action()
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
