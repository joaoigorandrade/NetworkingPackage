import Foundation
import Testing
@testable import Networking
import NetworkingTestSupport

private enum TestError: Error {
    case boom
}

@Suite("WebSocketClient")
struct WebSocketClientTests {
    private let url = URL(string: "wss://example.com/realtime/v1")!

    @Test func connectResumesTaskAndMarksClientConnected() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)

        #expect(client.isConnected == false)
        try await client.connect()

        #expect(client.isConnected == true)
        #expect(factory.taskCount() == 1)
        #expect(await factory.createdTasks()[0].wasResumed())

        await client.close()
    }

    @Test func sendForwardsMessageToTask() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)
        try await client.connect()

        try await client.send(.string("hello"))
        try await client.send(.data(Data("payload".utf8)))

        let sent = await factory.createdTasks()[0].sentMessages()
        #expect(sent == [.string("hello"), .data(Data("payload".utf8))])

        await client.close()
    }

    @Test func sendBeforeConnectThrowsNotConnected() async {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)

        await #expect(throws: WebSocketError.notConnected) {
            try await client.send(.string("hello"))
        }
    }

    @Test func messagesYieldsInboundMessagesInOrder() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)
        try await client.connect()

        let collector = Task { () -> [WebSocketMessage] in
            var received: [WebSocketMessage] = []
            for try await message in client.messages() {
                received.append(message)
                if received.count == 2 { break }
            }
            return received
        }

        let task = factory.createdTasks()[0]
        await task.emit(.string("first"))
        await task.emit(.data(Data("second".utf8)))

        #expect(try await collector.value == [.string("first"), .data(Data("second".utf8))])

        await client.close()
    }

    @Test func inboundFailureSurfacesInStream() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(
            configuration: makeConfiguration(maxReconnectAttempts: 0),
            factory: factory
        )
        try await client.connect()

        let collector = Task { () -> Error? in
            do {
                for try await _ in client.messages() {}
                return nil
            } catch {
                return error
            }
        }

        await factory.createdTasks()[0].fail(TestError.boom)

        let error = await collector.value
        #expect(error as? WebSocketError == .transportFailure("boom"))
        #expect(client.isConnected == false)
    }

    @Test func closeClosesTaskAndFinishesStreamWithoutError() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)
        try await client.connect()

        let collector = Task { () -> Error? in
            do {
                for try await _ in client.messages() {}
                return nil
            } catch {
                return error
            }
        }

        await client.close()

        #expect(await collector.value == nil)
        #expect(client.isConnected == false)
        #expect(await factory.createdTasks()[0].wasClosed())
        #expect(await factory.createdTasks()[0].closeCodeUsed() == .normalClosure)
    }

    @Test func reconnectCreatesNewTaskAfterFailure() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(
            configuration: makeConfiguration(maxReconnectAttempts: 3, reconnectBackoff: 0.01),
            factory: factory
        )
        try await client.connect()

        let collector = Task { () -> [WebSocketMessage] in
            var received: [WebSocketMessage] = []
            for try await message in client.messages() {
                received.append(message)
                if received.count == 1 { break }
            }
            return received
        }

        await factory.createdTasks()[0].fail(TestError.boom)
        try await waitUntil { factory.taskCount() >= 2 }

        #expect(factory.taskCount() == 2)
        #expect(client.isConnected == true)
        #expect(await factory.createdTasks()[1].wasResumed())

        await factory.createdTasks()[1].emit(.string("after-reconnect"))
        #expect(try await collector.value == [.string("after-reconnect")])

        await client.close()
    }

    @Test func reconnectLimitExceededFinishesStreamWithError() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(
            configuration: makeConfiguration(maxReconnectAttempts: 1, reconnectBackoff: 0.01),
            factory: factory
        )
        try await client.connect()

        let collector = Task { () -> Error? in
            do {
                for try await _ in client.messages() {}
                return nil
            } catch {
                return error
            }
        }

        await factory.createdTasks()[0].fail(TestError.boom)
        try await waitUntil { factory.taskCount() >= 2 }
        await factory.createdTasks()[1].fail(TestError.boom)

        let error = await collector.value
        #expect(error as? WebSocketError == .reconnectLimitExceeded(attempts: 1))
        #expect(client.isConnected == false)
    }

    @Test func handshakeRequestCarriesHeadersAndSubprotocols() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(
            configuration: makeConfiguration(
                headers: ["Authorization": "Bearer token"],
                subprotocols: ["realtime", "json"]
            ),
            factory: factory
        )
        try await client.connect()

        let request = factory.lastRequest()
        #expect(request?.url == url)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "realtime, json")
        #expect(request?.timeoutInterval == 30)

        await client.close()
    }

    @Test func pingKeepaliveSendsPings() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(
            configuration: makeConfiguration(pingInterval: 0.05),
            factory: factory
        )
        try await client.connect()

        try await waitUntil { await factory.createdTasks()[0].pingCount() >= 1 }
        #expect(await factory.createdTasks()[0].pingCount() >= 1)

        await client.close()
    }

    @Test func cancellingConsumerCancelsSocket() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = URLSessionWebSocketClient(configuration: makeConfiguration(), factory: factory)
        try await client.connect()

        let consumer = Task { () -> Void in
            for try await _ in client.messages() {}
        }
        consumer.cancel()

        try await waitUntil { await factory.createdTasks()[0].wasClosed() }
        #expect(await factory.createdTasks()[0].wasClosed())
    }

    // MARK: - Helpers

    private func makeConfiguration(
        headers: [String: String] = [:],
        subprotocols: [String] = [],
        timeoutInterval: TimeInterval = 30,
        pingInterval: TimeInterval? = nil,
        maxReconnectAttempts: Int = 5,
        reconnectBackoff: TimeInterval = 0.5
    ) -> WebSocketConfiguration {
        WebSocketConfiguration(
            url: url,
            headers: headers,
            subprotocols: subprotocols,
            timeoutInterval: timeoutInterval,
            pingInterval: pingInterval,
            maxReconnectAttempts: maxReconnectAttempts,
            reconnectBackoff: reconnectBackoff
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition was not met before the timeout")
    }
}
