import XCTest
import SMB2

@testable import AMSMB2

final class CallbackLifetimeTests: XCTestCase {
    func testCallbackStateCompletesExactlyOnce() {
        var handledStatuses: [Int32] = []
        var state: SMB2CallbackState? = SMB2CallbackState { status, _ in
            handledStatuses.append(status)
        }
        weak var weakState = state
        var token: SMB2RetainedCallback? = SMB2RetainedCallback(state: state!)

        SMB2RetainedCallback.complete(
            opaquePointer: token!.opaquePointer,
            status: 7,
            commandData: nil
        )
        SMB2RetainedCallback.complete(
            opaquePointer: token!.opaquePointer,
            status: 9,
            commandData: nil
        )
        XCTAssertEqual(handledStatuses, [7])
        XCTAssertEqual(state?.result, 7)
        XCTAssertTrue(state?.isFinished == true)

        token?.releaseCBarrierOwnership()
        token = nil
        state = nil
        XCTAssertNil(weakState)
    }

    func testSubmitFailureCanReleaseWithoutCallback() {
        var state: SMB2CallbackState? = SMB2CallbackState { _, _ in
            XCTFail("An immediately rejected submission must not invoke its callback")
        }
        weak var weakState = state
        var token: SMB2RetainedCallback? = SMB2RetainedCallback(state: state!)

        token?.releaseCBarrierOwnership()
        token = nil
        state = nil
        XCTAssertNil(weakState)
    }

    func testTimeoutAndCancellationStatusesFinishTheToken() {
        for status in [Int32(bitPattern: SMB2_STATUS_IO_TIMEOUT), Int32(bitPattern: SMB2_STATUS_CANCELLED)] {
            let state = SMB2CallbackState { _, _ in }
            let token = SMB2RetainedCallback(state: state)

            SMB2RetainedCallback.complete(
                opaquePointer: token.opaquePointer,
                status: status,
                commandData: nil
            )
            XCTAssertTrue(state.isFinished)
            XCTAssertEqual(state.status, UInt32(bitPattern: status))
            token.releaseCBarrierOwnership()
        }
    }

    func testNoEventPollingServicesLibSMB2Timeout() throws {
        var callbackPointer: UnsafeMutableRawPointer?
        var zeroEventServiceCount = 0
        var systemCalls = SMB2ContextSystemCalls.live
        systemCalls.pollOne = { _, _ in 0 }
        systemCalls.service = { context, revents in
            XCTAssertEqual(revents, 0)
            zeroEventServiceCount += 1
            SMB2Client.generic_handler(
                context,
                Int32(bitPattern: SMB2_STATUS_IO_TIMEOUT),
                nil,
                callbackPointer
            )
            return 0
        }
        let context = try SMB2Client(timeout: 1, systemCalls: systemCalls)

        XCTAssertThrowsError(
            try context.async_await { _, pointer in
                callbackPointer = pointer
                return 0
            }
        )
        XCTAssertEqual(zeroEventServiceCount, 1)
    }

    func testServiceErrorDestroysOriginalContextOnce() throws {
        var destroyCount = 0
        var destroyedPointer: UnsafeMutablePointer<smb2_context>?
        var systemCalls = SMB2ContextSystemCalls.live
        systemCalls.service = { _, _ in -1 }
        systemCalls.destroy = { context in
            destroyCount += 1
            destroyedPointer = context
            smb2_destroy_context(context)
        }
        var context: SMB2Client? = try SMB2Client(timeout: 0, systemCalls: systemCalls)
        let originalPointer = context?.context

        XCTAssertThrowsError(try context?.service(revents: 0))
        XCTAssertNil(context?.context)
        XCTAssertEqual(destroyedPointer, originalPointer)
        XCTAssertEqual(destroyCount, 1)

        context = nil
        XCTAssertEqual(destroyCount, 1)
    }

    func testTimeoutIsAppliedToLibSMB2() throws {
        var configuredTimeouts: [Int32] = []
        var systemCalls = SMB2ContextSystemCalls.live
        systemCalls.setTimeout = { _, seconds in
            configuredTimeouts.append(seconds)
        }
        let context = try SMB2Client(timeout: 1.2, systemCalls: systemCalls)

        context.timeout = 0

        XCTAssertEqual(configuredTimeouts, [2, 0])
    }

    func testEmptyPasswordUsesAbsentPasswordAndPreservesNonemptyPassword() throws {
        let client = try SMB2Client(timeout: 5)
        client.password = "secret"
        XCTAssertEqual(client.password, "secret")
        client.password = ""
        XCTAssertNil(client.context?.pointee.password)
    }

    func testFileHandleCloseRunsExactlyOnce() {
        let state = SMB2FileHandleState(handle: OpaquePointer(bitPattern: 0x1234))
        var closedHandles: [OpaquePointer] = []

        state.close { closedHandles.append($0) }
        state.close { closedHandles.append($0) }

        XCTAssertEqual(closedHandles, [OpaquePointer(bitPattern: 0x1234)!])
        XCTAssertTrue(state.isClosed)
    }

    func testFileHandleCloseWaitsForActiveOperation() throws {
        let state = SMB2FileHandleState(handle: OpaquePointer(bitPattern: 0x5678))
        let operationStarted = DispatchSemaphore(value: 0)
        let allowOperationToFinish = DispatchSemaphore(value: 0)
        let closeStarted = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "CallbackLifetimeTests", attributes: .concurrent)

        queue.async {
            try? state.withOpenHandle { _ in
                operationStarted.signal()
                allowOperationToFinish.wait()
            }
        }
        XCTAssertEqual(operationStarted.wait(timeout: .now() + 1), .success)

        queue.async {
            closeStarted.signal()
            state.close { _ in }
            closeFinished.signal()
        }
        XCTAssertEqual(closeStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(closeFinished.wait(timeout: .now() + 0.05), .timedOut)

        allowOperationToFinish.signal()
        XCTAssertEqual(closeFinished.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try state.withOpenHandle { _ in })
    }
}
