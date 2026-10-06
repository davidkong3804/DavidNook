import XCTest
@testable import DavidNookCore

final class FakeVideoFrameSourceTests: XCTestCase {
    func testEventsFlowToTheMachine() async {
        let source = FakeVideoFrameSource()
        var machine = VideoCapsuleStateMachine()
        var stream = source.events.makeAsyncIterator()

        machine.handle(.requestPicker, at: 0)
        source.start()
        XCTAssertEqual(source.startCount, 1)
        source.emit(.started(aspectRatio: 1.6))
        source.emit(.sourceClosed)
        var t = 0.0
        for _ in 0..<2 {
            if let e = await stream.next() { t += 1; machine.handle(.source(e), at: t) }
        }
        XCTAssertEqual(machine.state, .sourceClosed)
    }

    func testStopCountsAndFinishEndsTheStream() async {
        let source = FakeVideoFrameSource()
        var it = source.events.makeAsyncIterator()
        source.stop()
        XCTAssertEqual(source.stopCount, 1)
        source.finish()
        let next = await it.next()
        XCTAssertNil(next)
    }
}
