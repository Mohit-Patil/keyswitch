import Foundation
import CoreGraphics
import XCTest
@testable import KeySwitch

final class KeyboardEngineTests: XCTestCase {
    func testBridgeAcceptsOnlyExpectedLoopbackDevToolsSocketURLs() throws {
        let acceptedValues = [
            "ws://127.0.0.1:9348/devtools/page/ABC123",
            "wss://127.0.0.1:9348/devtools/page/ABC123",
            "ws://[::1]:9348/devtools/page/ABC123",
        ]

        for value in acceptedValues {
            XCTAssertNotNil(
                CodexBridgeEndpointPolicy.validatedWebSocketURL(value, debugPort: 9348),
                "Expected \(value) to be accepted"
            )
        }
    }

    func testBridgeRejectsRemoteMalformedAndMismatchedDevToolsSocketURLs() {
        let rejectedValues = [
            "ws://example.com:9348/devtools/page/ABC123",
            "ws://127.0.0.1.example.com:9348/devtools/page/ABC123",
            "ws://localhost:9348/devtools/page/ABC123",
            "ws://127.0.0.1:9349/devtools/page/ABC123",
            "ws://127.0.0.1/devtools/page/ABC123",
            "http://127.0.0.1:9348/devtools/page/ABC123",
            "ws://user@127.0.0.1:9348/devtools/page/ABC123",
            "ws://127.0.0.1:9348/devtools/browser/ABC123",
            "ws://127.0.0.1:9348/devtools/page/",
            "ws://127.0.0.1:9348/devtools/page/ABC%2F123",
            "ws://127.0.0.1:9348/devtools/page/ABC.123",
            "ws://127.0.0.1:9348/devtools/page/ABC123?redirect=example.com",
            "ws://127.0.0.1:9348/devtools/page/ABC123#fragment",
            "not a URL",
        ]

        for value in rejectedValues {
            XCTAssertNil(
                CodexBridgeEndpointPolicy.validatedWebSocketURL(value, debugPort: 9348),
                "Expected \(value) to be rejected"
            )
        }
        XCTAssertNil(
            CodexBridgeEndpointPolicy.validatedWebSocketURL(
                "ws://127.0.0.1:9348/devtools/page/ABC123",
                debugPort: 0
            )
        )
        XCTAssertNil(CodexBridgeEndpointPolicy.discoveryURL(debugPort: 65_536))
    }

    func testBridgeRejectsRedirectedDiscoveryResponses() throws {
        let expected = try XCTUnwrap(URL(string: "http://127.0.0.1:9348/json/list"))
        XCTAssertTrue(
            CodexBridgeEndpointPolicy.isExpectedDiscoveryResponseURL(
                expected,
                debugPort: 9348
            )
        )

        let rejectedValues = [
            "http://example.com:9348/json/list",
            "http://127.0.0.1:9349/json/list",
            "https://127.0.0.1:9348/json/list",
            "http://127.0.0.1:9348/json/list?source=redirect",
            "http://127.0.0.1:9348/json/version",
        ]
        for value in rejectedValues {
            XCTAssertFalse(
                CodexBridgeEndpointPolicy.isExpectedDiscoveryResponseURL(
                    URL(string: value),
                    debugPort: 9348
                ),
                "Expected \(value) to be rejected"
            )
        }
    }

    func testBridgeCapsDiscoveryResponseAtOneMiB() {
        let limit = CodexBridgeEndpointPolicy.maximumDiscoveryResponseBytes
        XCTAssertEqual(limit, 1_048_576)
        XCTAssertTrue(
            CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
                currentByteCount: 0,
                incomingByteCount: limit
            )
        )
        XCTAssertTrue(
            CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
                currentByteCount: limit,
                incomingByteCount: 0
            )
        )
        XCTAssertFalse(
            CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
                currentByteCount: 0,
                incomingByteCount: limit + 1
            )
        )
        XCTAssertFalse(
            CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
                currentByteCount: limit,
                incomingByteCount: 1
            )
        )
        XCTAssertFalse(
            CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
                currentByteCount: -1,
                incomingByteCount: 1
            )
        )
    }

    func testBridgePollingKeepsLightingResponsiveAndThrottlesLayoutReads() {
        XCTAssertEqual(CodexBridgePollingPolicy.lightingIntervalMilliseconds, 900)
        XCTAssertFalse(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 0))
        XCTAssertFalse(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 1))
        XCTAssertFalse(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 2))
        XCTAssertTrue(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 3))
        XCTAssertFalse(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 4))
        XCTAssertTrue(CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: 6))
    }

    func testFnAlonePassesThroughWithoutActivatingLayer() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let fnDown = try modifierEvent(code: 63, flags: .maskSecondaryFn)
        let fnDownResult = engine.handle(type: .flagsChanged, event: fnDown)
        XCTAssertNotNil(fnDownResult)
        withExtendedLifetime(fnDown) {}

        let fnUp = try modifierEvent(code: 63, flags: [])
        let fnUpResult = engine.handle(type: .flagsChanged, event: fnUp)
        XCTAssertNotNil(fnUpResult)
        withExtendedLifetime(fnUp) {}

        XCTAssertTrue(layerStates.isEmpty)
    }

    func testHoldModeActivatesOnFnControlAndReleases() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var layerStates: [Bool] = []
        var controlEvents: [(MicroControl, Int)] = []
        engine.onLayerStateChanged = { layerStates.append($0) }
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)
        XCTAssertNil(engine.handle(type: .keyDown, event: try keyEvent(code: PhysicalKey.one.keyCode, isDown: true)))
        XCTAssertNil(engine.handle(type: .keyUp, event: try keyEvent(code: PhysicalKey.one.keyCode, isDown: false)))
        releaseDefaultShortcut(on: engine)

        XCTAssertEqual(layerStates, [true, false])
        XCTAssertEqual(controlEvents.count, 2)
        XCTAssertEqual(controlEvents[0].0, .agent0)
        XCTAssertEqual(controlEvents[0].1, 1)
        XCTAssertEqual(controlEvents[1].0, .agent0)
        XCTAssertEqual(controlEvents[1].1, 0)
    }

    func testToggleModeStaysActiveUntilSecondShortcutPress() throws {
        let engine = makeEngine(mode: .toggle, blockUnmapped: true)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        pressDefaultShortcut(on: engine)
        releaseDefaultShortcut(on: engine)
        XCTAssertNil(engine.handle(type: .keyDown, event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)))
        XCTAssertNil(engine.handle(type: .keyUp, event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: false)))
        pressDefaultShortcut(on: engine)

        XCTAssertEqual(layerStates, [true, false])
    }

    func testCustomOptionCommandShortcut() throws {
        let shortcut = ActivationShortcut(modifiers: [.option, .command])
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        _ = engine.handle(
            type: .flagsChanged,
            event: try modifierEvent(code: 58, flags: .maskAlternate)
        )
        XCTAssertTrue(layerStates.isEmpty)

        _ = engine.handle(
            type: .flagsChanged,
            event: try modifierEvent(code: 55, flags: [.maskAlternate, .maskCommand])
        )
        _ = engine.handle(
            type: .flagsChanged,
            event: try modifierEvent(code: 55, flags: .maskAlternate)
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testSingleControlShortcutActivatesAndReleasesHoldLayer() throws {
        let shortcut = ActivationShortcut(modifiers: [.control])
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let controlDown = try modifierEvent(code: 59, flags: .maskControl)
        XCTAssertNotNil(engine.handle(type: .flagsChanged, event: controlDown))
        withExtendedLifetime(controlDown) {}

        let controlUp = try modifierEvent(code: 59, flags: [])
        XCTAssertNotNil(engine.handle(type: .flagsChanged, event: controlUp))
        withExtendedLifetime(controlUp) {}

        XCTAssertEqual(layerStates, [true, false])
    }

    func testFnOnlyShortcutSuppressesGlobeAndActivatesLayer() throws {
        let shortcut = ActivationShortcut(modifiers: [.function])
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let fnDown = try modifierEvent(code: 63, flags: .maskSecondaryFn)
        XCTAssertNil(engine.handle(type: .flagsChanged, event: fnDown))
        withExtendedLifetime(fnDown) {}

        let fnUp = try modifierEvent(code: 63, flags: [])
        XCTAssertNil(engine.handle(type: .flagsChanged, event: fnUp))
        withExtendedLifetime(fnUp) {}

        XCTAssertEqual(layerStates, [true, false])
    }

    func testSingleRegularKeyActivatesHoldLayerAndConsumesBothTransitions() throws {
        let shortcut = ActivationShortcut(modifiers: [], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testRegularKeyToggleIgnoresAutoRepeat() throws {
        let shortcut = ActivationShortcut(modifiers: [], key: .g)
        let engine = makeEngine(mode: .toggle, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )

        let repeatedEvent = try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
        repeatedEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(engine.handle(type: .keyDown, event: repeatedEvent))

        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testModifiedRegularKeyRequiresTheRecordedModifiers() throws {
        let shortcut = ActivationShortcut(modifiers: [.control], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let unmatchedDown = try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: unmatchedDown))
        withExtendedLifetime(unmatchedDown) {}

        let unmatchedUp = try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
        XCTAssertNotNil(engine.handle(type: .keyUp, event: unmatchedUp))
        withExtendedLifetime(unmatchedUp) {}

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(
                    code: PhysicalKey.g.keyCode,
                    isDown: true,
                    flags: .maskControl
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testFnKeyChordOwnsFnSoGlobeDoesNotReceiveAnOrphanPress() throws {
        let shortcut = ActivationShortcut(modifiers: [.function], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: .maskSecondaryFn)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(
                    code: PhysicalKey.g.keyCode,
                    isDown: true,
                    flags: .maskSecondaryFn
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(
                    code: PhysicalKey.g.keyCode,
                    isDown: false,
                    flags: .maskSecondaryFn
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: [])
            )
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testModifiedRegularKeyDoesNotMatchAnUnrecordedExtraModifier() throws {
        let shortcut = ActivationShortcut(modifiers: [.control], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let event = try keyEvent(
            code: PhysicalKey.g.keyCode,
            isDown: true,
            flags: [.maskControl, .maskShift]
        )
        XCTAssertNotNil(engine.handle(type: .keyDown, event: event))
        withExtendedLifetime(event) {}
        XCTAssertTrue(layerStates.isEmpty)
    }

    func testNonMatchingActivationKeyStillUsesNormalActiveLayerHandling() throws {
        let unmappedShortcut = ActivationShortcut(modifiers: [.control], key: .g)
        let blockingEngine = makeEngine(
            mode: .hold,
            blockUnmapped: true,
            shortcut: unmappedShortcut
        )
        blockingEngine.toggleLayerFromMenu()
        XCTAssertNil(
            blockingEngine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )

        let mappedShortcut = ActivationShortcut(modifiers: [.control], key: .q)
        let mappedEngine = makeEngine(
            mode: .hold,
            blockUnmapped: true,
            shortcut: mappedShortcut
        )
        var controlEvents: [(MicroControl, Int)] = []
        mappedEngine.onControlEvent = { controlEvents.append(($0, $1)) }
        mappedEngine.toggleLayerFromMenu()

        XCTAssertNil(
            mappedEngine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
            )
        )
        XCTAssertNil(
            mappedEngine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: false)
            )
        )
        XCTAssertEqual(controlEvents.map(\.0), [.fastMode, .fastMode])
        XCTAssertEqual(controlEvents.map(\.1), [1, 0])
    }

    func testReleasingARequiredModifierEndsHoldAndStillConsumesTriggerKeyUp() throws {
        let shortcut = ActivationShortcut(modifiers: [.control], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(
                    code: PhysicalKey.g.keyCode,
                    isDown: true,
                    flags: .maskControl
                )
            )
        )

        let controlUp = try modifierEvent(code: 59, flags: [])
        XCTAssertNotNil(engine.handle(type: .flagsChanged, event: controlUp))
        withExtendedLifetime(controlUp) {}

        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )
        XCTAssertEqual(layerStates, [true, false])
    }

    func testTriggerKeyPressedBeforeModifierDoesNotActivate() throws {
        let shortcut = ActivationShortcut(modifiers: [.control], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        let keyDown = try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: keyDown))
        withExtendedLifetime(keyDown) {}

        _ = engine.handle(
            type: .flagsChanged,
            event: try modifierEvent(code: 59, flags: .maskControl)
        )

        let keyUp = try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
        XCTAssertNotNil(engine.handle(type: .keyUp, event: keyUp))
        withExtendedLifetime(keyUp) {}
        XCTAssertTrue(layerStates.isEmpty)
    }

    func testActivationKeyTakesPriorityOverAConflictingMapping() throws {
        let shortcut = ActivationShortcut(modifiers: [], key: .q)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        var controlEvents: [(MicroControl, Int)] = []
        engine.onLayerStateChanged = { layerStates.append($0) }
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(layerStates, [true, false])
        XCTAssertTrue(controlEvents.isEmpty)
    }

    func testEscapeCanBeUsedAsTheActivationKey() throws {
        let escape = PhysicalKey(keyCode: 53, displayName: "Escape", isModifier: false)
        let shortcut = ActivationShortcut(modifiers: [], key: escape)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(type: .keyDown, event: try keyEvent(code: 53, isDown: true))
        )
        XCTAssertNil(
            engine.handle(type: .keyUp, event: try keyEvent(code: 53, isDown: false))
        )

        XCTAssertEqual(layerStates, [true, false])
    }

    func testShortcutRecorderCapturesChordWithoutActivatingTheLayer() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var layerStates: [Bool] = []
        var capturedShortcut: (PhysicalKey, Set<ActivationModifier>)?
        engine.onLayerStateChanged = { layerStates.append($0) }
        engine.beginShortcutCapture(
            onCapture: { key, modifiers in
                capturedShortcut = (key, modifiers)
            },
            onCancel: {}
        )

        let fnDown = try modifierEvent(code: 63, flags: .maskSecondaryFn)
        XCTAssertNil(engine.handle(type: .flagsChanged, event: fnDown))
        withExtendedLifetime(fnDown) {}

        let controlDown = try modifierEvent(
            code: 59,
            flags: [.maskSecondaryFn, .maskControl]
        )
        XCTAssertNil(engine.handle(type: .flagsChanged, event: controlDown))
        withExtendedLifetime(controlDown) {}

        let qDown = try keyEvent(
            code: PhysicalKey.q.keyCode,
            isDown: true,
            flags: [.maskSecondaryFn, .maskControl]
        )
        XCTAssertNil(engine.handle(type: .keyDown, event: qDown))
        withExtendedLifetime(qDown) {}

        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(
                    code: PhysicalKey.q.keyCode,
                    isDown: false,
                    flags: [.maskSecondaryFn, .maskControl]
                )
            )
        )

        XCTAssertEqual(capturedShortcut?.0.keyCode, PhysicalKey.q.keyCode)
        XCTAssertEqual(capturedShortcut?.1, [.function, .control])
        XCTAssertTrue(layerStates.isEmpty)

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 59, flags: .maskSecondaryFn)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: [])
            )
        )
        pressDefaultShortcut(on: engine)
        XCTAssertEqual(layerStates, [true])
    }

    func testShortcutRecorderRefusesToWaitWithoutAnActiveEventTap() throws {
        let engine = KeyboardEngine(
            configuration: KeyboardEngineConfiguration(
                activationMode: .hold,
                activationShortcut: .standard,
                blockUnmappedKeys: true,
                bindings: KeyBinding.defaults
            )
        )
        var capturedKey: PhysicalKey?

        XCTAssertFalse(
            engine.beginShortcutCapture(
                onCapture: { key, _ in capturedKey = key },
                onCancel: {}
            )
        )

        let keyDown = try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: keyDown))
        withExtendedLifetime(keyDown) {}
        XCTAssertNil(capturedKey)
    }

    func testShortcutRecorderOwnsACommandSpaceSystemChord() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var capturedShortcut: (PhysicalKey, Set<ActivationModifier>)?
        engine.beginShortcutCapture(
            onCapture: { key, modifiers in
                capturedShortcut = (key, modifiers)
            },
            onCancel: {}
        )

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 55, flags: .maskCommand)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.space.keyCode, isDown: true, flags: .maskCommand)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.space.keyCode, isDown: false, flags: .maskCommand)
            )
        )

        XCTAssertEqual(capturedShortcut?.0, PhysicalKey.space)
        XCTAssertEqual(capturedShortcut?.1, [.command])
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 55, flags: [])
            )
        )
    }

    func testTapTimeoutCancelsShortcutRecording() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var cancellationCount = 0
        engine.beginShortcutCapture(
            onCapture: { _, _ in XCTFail("A disabled tap must not complete capture") },
            onCancel: { cancellationCount += 1 }
        )

        let timeoutEvent = try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .tapDisabledByTimeout, event: timeoutEvent))
        withExtendedLifetime(timeoutEvent) {}
        XCTAssertEqual(cancellationCount, 1)

        let nextKeyDown = try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: nextKeyDown))
        withExtendedLifetime(nextKeyDown) {}
    }

    func testShortcutRecorderFinishesAPreviouslyCapturedKey() throws {
        let shortcut = ActivationShortcut(modifiers: [], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )
        engine.beginShortcutCapture(onCapture: { _, _ in }, onCancel: {})
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )
        engine.cancelShortcutCapture()

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )
        XCTAssertEqual(layerStates, [true, false, true])
    }

    func testCapturedActivationKeyUpIsSuppressedAfterConfigurationChanges() throws {
        let shortcut = ActivationShortcut(modifiers: [], key: .g)
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
            )
        )
        engine.update(
            configuration: KeyboardEngineConfiguration(
                activationMode: .hold,
                activationShortcut: .standard,
                blockUnmappedKeys: true,
                bindings: KeyBinding.defaults
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.g.keyCode, isDown: false)
            )
        )

        let nextKeyDown = try keyEvent(code: PhysicalKey.g.keyCode, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: nextKeyDown))
        withExtendedLifetime(nextKeyDown) {}
    }

    func testRightCommandCanBeUsedAsSubmit() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 54,
                    flags: [.maskSecondaryFn, .maskControl, .maskCommand]
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 54, flags: [.maskSecondaryFn, .maskControl])
            )
        )

        XCTAssertEqual(controlEvents.count, 2)
        XCTAssertEqual(controlEvents[0].0, .submit)
        XCTAssertEqual(controlEvents[0].1, 1)
        XCTAssertEqual(controlEvents[1].0, .submit)
        XCTAssertEqual(controlEvents[1].1, 0)
    }

    func testUnmappedRegularKeysRespectBlockingSetting() throws {
        let blockingEngine = makeEngine(mode: .hold, blockUnmapped: true)
        pressDefaultShortcut(on: blockingEngine)
        XCTAssertNil(blockingEngine.handle(type: .keyDown, event: try keyEvent(code: 6, isDown: true)))

        let passingEngine = makeEngine(mode: .hold, blockUnmapped: false)
        pressDefaultShortcut(on: passingEngine)
        let passingEvent = try keyEvent(code: 6, isDown: true)
        let result = passingEngine.handle(type: .keyDown, event: passingEvent)
        XCTAssertNotNil(result)
        withExtendedLifetime(passingEvent) {}
    }

    func testBlockedRegularKeyReleaseStaysSuppressedAfterLayerDeactivation() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        pressDefaultShortcut(on: engine)

        XCTAssertNil(
            engine.handle(type: .keyDown, event: try keyEvent(code: 6, isDown: true))
        )
        releaseDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(type: .keyUp, event: try keyEvent(code: 6, isDown: false))
        )

        let nextKeyDown = try keyEvent(code: 6, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: nextKeyDown))
        withExtendedLifetime(nextKeyDown) {}
    }

    func testMappedRegularKeyReleaseStaysSuppressedAfterLayerDeactivation() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }
        pressDefaultShortcut(on: engine)

        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: true)
            )
        )
        releaseDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.q.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(controlEvents.map(\.0), [.fastMode, .fastMode])
        XCTAssertEqual(controlEvents.map(\.1), [1, 0])
    }

    func testEscapeReleaseStaysSuppressedAfterItDeactivatesLayer() throws {
        let engine = makeEngine(mode: .toggle, blockUnmapped: true)
        engine.toggleLayerFromMenu()

        XCTAssertNil(
            engine.handle(type: .keyDown, event: try keyEvent(code: 53, isDown: true))
        )
        XCTAssertNil(
            engine.handle(type: .keyUp, event: try keyEvent(code: 53, isDown: false))
        )

        let nextEscapeDown = try keyEvent(code: 53, isDown: true)
        XCTAssertNotNil(engine.handle(type: .keyDown, event: nextEscapeDown))
        withExtendedLifetime(nextEscapeDown) {}
    }

    func testMappedModifierReleaseStaysSuppressedAcrossConfigurationUpdate() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        pressDefaultShortcut(on: engine)

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: PhysicalKey.leftShift.keyCode,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )
        engine.update(
            configuration: KeyboardEngineConfiguration(
                activationMode: .hold,
                activationShortcut: ActivationShortcut(modifiers: [.shift]),
                blockUnmappedKeys: true,
                bindings: KeyBinding.defaults
            )
        )

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: PhysicalKey.leftShift.keyCode, flags: [])
            )
        )
    }

    func testMappedModifierReleaseUsesPhysicalKeyWhenBothShiftsAreHeld() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }
        pressDefaultShortcut(on: engine)

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 56,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 60,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 56,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 60,
                    flags: [.maskSecondaryFn, .maskControl]
                )
            )
        )

        XCTAssertEqual(controlEvents.map(\.0), [.dialPress, .dialPress])
        XCTAssertEqual(controlEvents.map(\.1), [1, 0])
    }

    func testFnOnlyReleaseStaysSuppressedWhenCaptureStartsWhileFnIsHeld() throws {
        let shortcut = ActivationShortcut(modifiers: [.function])
        let engine = makeEngine(mode: .hold, blockUnmapped: true, shortcut: shortcut)
        var layerStates: [Bool] = []
        engine.onLayerStateChanged = { layerStates.append($0) }

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: .maskSecondaryFn)
            )
        )
        engine.beginShortcutCapture(onCapture: { _, _ in }, onCancel: {})
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: [])
            )
        )
        engine.cancelShortcutCapture()

        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: .maskSecondaryFn)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 63, flags: [])
            )
        )
        XCTAssertEqual(layerStates, [true, false, true, false])
    }

    func testUnmappedModifierIsSuppressedThroughItsRelease() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)

        pressDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: 56,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )

        // Releasing Control turns the layer off, but the matching Shift
        // release remains swallowed because macOS never received its press.
        _ = engine.handle(
            type: .flagsChanged,
            event: try modifierEvent(code: 59, flags: [.maskSecondaryFn, .maskShift])
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(code: 56, flags: .maskSecondaryFn)
            )
        )
    }

    func testDefaultMappingsCoverEveryControlWithoutDuplicates() {
        XCTAssertEqual(Set(KeyBinding.defaults.map(\.control)), Set(MicroControl.allCases))

        let assignedKeys = KeyBinding.defaults.compactMap(\.physicalKey)
        XCTAssertEqual(Set(assignedKeys).count, assignedKeys.count)
    }

    func testShippingDialDefaultsUseTheTopLeftKeyboardCluster() {
        XCTAssertEqual(
            KeyBinding.defaults.first(where: { $0.control == .dialPrevious })?.physicalKey,
            .tab
        )
        XCTAssertEqual(
            KeyBinding.defaults.first(where: { $0.control == .dialNext })?.physicalKey,
            .backtick
        )
        XCTAssertEqual(
            KeyBinding.defaults.first(where: { $0.control == .dialPress })?.physicalKey,
            .leftShift
        )
    }

    func testDialPreviousEmitsOneClickAndIgnoresAutoRepeat() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)

        let keyDown = try keyEvent(code: PhysicalKey.tab.keyCode, isDown: true)
        XCTAssertNil(engine.handle(type: .keyDown, event: keyDown))

        let repeatedKeyDown = try keyEvent(code: PhysicalKey.tab.keyCode, isDown: true)
        repeatedKeyDown.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(engine.handle(type: .keyDown, event: repeatedKeyDown))

        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.tab.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(controlEvents.count, 2)
        XCTAssertEqual(controlEvents[0].0, .dialPrevious)
        XCTAssertEqual(controlEvents[0].1, 1)
        XCTAssertEqual(controlEvents[1].0, .dialPrevious)
        XCTAssertEqual(controlEvents[1].1, 0)
    }

    func testDialNextEmitsOneClickFromBacktickAndIgnoresAutoRepeat() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)

        let keyDown = try keyEvent(code: PhysicalKey.backtick.keyCode, isDown: true)
        XCTAssertNil(
            engine.handle(type: .keyDown, event: keyDown)
        )

        let repeatedKeyDown = try keyEvent(code: PhysicalKey.backtick.keyCode, isDown: true)
        repeatedKeyDown.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(
            engine.handle(type: .keyDown, event: repeatedKeyDown)
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.backtick.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(controlEvents.map(\.0), [.dialNext, .dialNext])
        XCTAssertEqual(controlEvents.map(\.1), [1, 0])
    }

    func testLeftShiftSupportsDialPressAndHoldRelease() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: PhysicalKey.leftShift.keyCode,
                    flags: [.maskSecondaryFn, .maskControl, .maskShift]
                )
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .flagsChanged,
                event: try modifierEvent(
                    code: PhysicalKey.leftShift.keyCode,
                    flags: [.maskSecondaryFn, .maskControl]
                )
            )
        )

        XCTAssertEqual(controlEvents.map(\.0), [.dialPress, .dialPress])
        XCTAssertEqual(controlEvents.map(\.1), [1, 0])
    }

    func testStickDirectionRemainsMomentary() throws {
        let engine = makeEngine(mode: .hold, blockUnmapped: true)
        var controlEvents: [(MicroControl, Int)] = []
        engine.onControlEvent = { controlEvents.append(($0, $1)) }

        pressDefaultShortcut(on: engine)
        XCTAssertNil(
            engine.handle(
                type: .keyDown,
                event: try keyEvent(code: PhysicalKey.l.keyCode, isDown: true)
            )
        )
        XCTAssertNil(
            engine.handle(
                type: .keyUp,
                event: try keyEvent(code: PhysicalKey.l.keyCode, isDown: false)
            )
        )

        XCTAssertEqual(controlEvents.count, 2)
        XCTAssertEqual(controlEvents[0].0, .stickRight)
        XCTAssertEqual(controlEvents[0].1, 1)
        XCTAssertEqual(controlEvents[1].0, .stickRight)
        XCTAssertEqual(controlEvents[1].1, 0)
    }

    func testDefaultStickMappingsUseIJKLCluster() {
        let bindings = Dictionary(
            uniqueKeysWithValues: KeyBinding.defaults.compactMap { binding in
                binding.physicalKey.map { (binding.control, $0) }
            }
        )

        XCTAssertEqual(bindings[.stickUp], .i)
        XCTAssertEqual(bindings[.stickLeft], .j)
        XCTAssertEqual(bindings[.stickDown], .k)
        XCTAssertEqual(bindings[.stickRight], .l)
    }

    func testDefaultAgentsUseNumberRowAndCommandsUseQWER() {
        let bindings = Dictionary(
            uniqueKeysWithValues: KeyBinding.defaults.compactMap { binding in
                binding.physicalKey.map { (binding.control, $0) }
            }
        )

        XCTAssertEqual(bindings[.agent0], .one)
        XCTAssertEqual(bindings[.agent1], .two)
        XCTAssertEqual(bindings[.agent2], .three)
        XCTAssertEqual(bindings[.agent3], .four)
        XCTAssertEqual(bindings[.agent4], .five)
        XCTAssertEqual(bindings[.agent5], .six)
        XCTAssertEqual(bindings[.fastMode], .q)
        XCTAssertEqual(bindings[.approve], .w)
        XCTAssertEqual(bindings[.reject], .e)
        XCTAssertEqual(bindings[.fork], .r)
    }

    func testFormerShippingAgentAndCommandDefaultsMigrateToNewLayout() throws {
        var legacyBindings = KeyBinding.defaults
        let legacyKeys: [MicroControl: PhysicalKey] = [
            .agent0: .q, .agent1: .w, .agent2: .e,
            .agent3: .r, .agent4: .t, .agent5: .y,
            .fastMode: .a, .approve: .s, .reject: .d, .fork: .f,
        ]
        for index in legacyBindings.indices {
            if let legacyKey = legacyKeys[legacyBindings[index].control] {
                legacyBindings[index].physicalKey = legacyKey
            }
        }

        let configuration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: legacyBindings
        )
        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.bindings, KeyBinding.defaults)
    }

    func testCustomizedFormerAgentClusterIsNotMigrated() throws {
        var legacyBindings = KeyBinding.defaults
        let legacyKeys: [MicroControl: PhysicalKey] = [
            .agent0: .g, .agent1: .w, .agent2: .e,
            .agent3: .r, .agent4: .t, .agent5: .y,
            .fastMode: .a, .approve: .s, .reject: .d, .fork: .f,
        ]
        for index in legacyBindings.indices {
            if let legacyKey = legacyKeys[legacyBindings[index].control] {
                legacyBindings[index].physicalKey = legacyKey
            }
        }

        let configuration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: legacyBindings
        )
        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .agent0 })?.physicalKey, .g)
        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .agent1 })?.physicalKey, .w)
        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .fastMode })?.physicalKey, .a)
    }

    func testLegacyArrowStickDefaultsMigrateToIJKL() throws {
        var legacyBindings = KeyBinding.defaults
        legacyBindings[legacyBindings.firstIndex(where: { $0.control == .stickUp })!].physicalKey = .upArrow
        legacyBindings[legacyBindings.firstIndex(where: { $0.control == .stickRight })!].physicalKey = .rightArrow
        legacyBindings[legacyBindings.firstIndex(where: { $0.control == .stickDown })!].physicalKey = .downArrow
        legacyBindings[legacyBindings.firstIndex(where: { $0.control == .stickLeft })!].physicalKey = .leftArrow

        let legacyConfiguration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: legacyBindings
        )
        let data = try JSONEncoder().encode(legacyConfiguration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .stickUp })?.physicalKey, .i)
        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .stickLeft })?.physicalKey, .j)
        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .stickDown })?.physicalKey, .k)
        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .stickRight })?.physicalKey, .l)
    }

    func testCustomStickMappingIsNotMigrated() throws {
        var savedBindings = KeyBinding.defaults
        savedBindings[savedBindings.firstIndex(where: { $0.control == .stickUp })!].physicalKey = .i
        savedBindings[savedBindings.firstIndex(where: { $0.control == .stickRight })!].physicalKey = .rightArrow
        savedBindings[savedBindings.firstIndex(where: { $0.control == .stickDown })!].physicalKey = .downArrow
        savedBindings[savedBindings.firstIndex(where: { $0.control == .stickLeft })!].physicalKey = .leftArrow

        let configuration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: savedBindings
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.bindings.first(where: { $0.control == .stickUp })?.physicalKey, .i)
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .stickRight })?.physicalKey,
            .rightArrow
        )
    }

    func testSavedMappingsGainNewControlsDuringDecoding() throws {
        let legacyConfiguration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: Array(KeyBinding.defaults.prefix(12))
        )

        let data = try JSONEncoder().encode(legacyConfiguration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(Set(decoded.bindings.map(\.control)), Set(MicroControl.allCases))
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialNext })?.physicalKey,
            .backtick
        )
    }

    func testNewDefaultsDoNotTakeKeysFromSavedMappings() throws {
        var legacyBindings = Array(KeyBinding.defaults.prefix(12))
        legacyBindings[0].physicalKey = .backtick
        let legacyConfiguration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: legacyBindings
        )

        let data = try JSONEncoder().encode(legacyConfiguration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .agent0 })?.physicalKey,
            .backtick
        )
        XCTAssertNil(
            decoded.bindings.first(where: { $0.control == .dialNext })?.physicalKey
        )
    }

    func testLegacyGHDialDefaultsMigrateToTheShippingCluster() throws {
        var legacyBindings = KeyBinding.defaults
        legacyBindings[
            legacyBindings.firstIndex(where: { $0.control == .dialPrevious })!
        ].physicalKey = nil
        legacyBindings[
            legacyBindings.firstIndex(where: { $0.control == .dialNext })!
        ].physicalKey = .g
        legacyBindings[
            legacyBindings.firstIndex(where: { $0.control == .dialPress })!
        ].physicalKey = .h

        let legacyConfiguration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: legacyBindings
        )
        let data = try JSONEncoder().encode(legacyConfiguration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPrevious })?.physicalKey,
            .tab
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialNext })?.physicalKey,
            .backtick
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPress })?.physicalKey,
            .leftShift
        )
    }

    func testPreviousCapsLockDialDefaultMigratesToBacktick() throws {
        var previousShippingBindings = KeyBinding.defaults
        previousShippingBindings[
            previousShippingBindings.firstIndex(where: { $0.control == .dialNext })!
        ].physicalKey = .capsLock

        let configuration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: previousShippingBindings
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPrevious })?.physicalKey,
            .tab
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialNext })?.physicalKey,
            .backtick
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPress })?.physicalKey,
            .leftShift
        )
    }

    func testCustomizedLegacyDialMappingsAreNotMigrated() throws {
        let customPrevious = PhysicalKey(keyCode: 6, displayName: "Z", isModifier: false)
        var customBindings = KeyBinding.defaults
        customBindings[
            customBindings.firstIndex(where: { $0.control == .dialPrevious })!
        ].physicalKey = customPrevious
        customBindings[
            customBindings.firstIndex(where: { $0.control == .dialNext })!
        ].physicalKey = .g
        customBindings[
            customBindings.firstIndex(where: { $0.control == .dialPress })!
        ].physicalKey = .h

        let configuration = AppConfiguration(
            activationMode: .hold,
            activationShortcut: .standard,
            showHUD: true,
            blockUnmappedKeys: true,
            debugPort: 9348,
            bindings: customBindings
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPrevious })?.physicalKey,
            customPrevious
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialNext })?.physicalKey,
            .g
        )
        XCTAssertEqual(
            decoded.bindings.first(where: { $0.control == .dialPress })?.physicalKey,
            .h
        )
    }

    func testKeySwitchSettingsRoundTrip() throws {
        var configuration = AppConfiguration.default
        configuration.layerAutoExitTimeout = .fiveSeconds
        configuration.lightingBrightness = 0.64
        configuration.animatedAgentLighting = true
        configuration.autoDimTimeout = .fifteenMinutes
        configuration.hudAppearance = .light
        configuration.expandedHUDSize = .extraLarge
        configuration.showMenuBarAgentStatus = false
        configuration.menuBarIndicatorSize = .extraLarge
        configuration.focusCodexOnSingleTap = true
        configuration.hasCompletedFirstRunSetup = true

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.layerAutoExitTimeout, .fiveSeconds)
        XCTAssertEqual(decoded.lightingBrightness, 0.64, accuracy: 0.001)
        XCTAssertTrue(decoded.animatedAgentLighting)
        XCTAssertEqual(decoded.autoDimTimeout, .fifteenMinutes)
        XCTAssertEqual(decoded.hudAppearance, .light)
        XCTAssertEqual(decoded.expandedHUDSize, .extraLarge)
        XCTAssertFalse(decoded.showMenuBarAgentStatus)
        XCTAssertEqual(decoded.menuBarIndicatorSize, .extraLarge)
        XCTAssertTrue(decoded.focusCodexOnSingleTap)
        XCTAssertTrue(decoded.hasCompletedFirstRunSetup)
    }

    func testLegacySettingsGainDefaultLayerAutoExitTimeout() throws {
        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "layerAutoExitTimeout")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded.layerAutoExitTimeout, .threeSeconds)
    }

    func testLegacyFloatingStatusPillSettingsAreIgnored() throws {
        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject["statusHUDMode"] = "always"
        legacyObject["statusHUDHideDelay"] = 10

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded, .default)
    }

    func testLegacySettingsShowAgentStatusInMenuBarByDefault() throws {
        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "showMenuBarAgentStatus")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertTrue(decoded.showMenuBarAgentStatus)
    }

    func testLegacySettingsGainStandardMenuBarIndicatorSize() throws {
        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "menuBarIndicatorSize")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded.menuBarIndicatorSize, .standard)
    }

    func testLegacySettingsGainStandardExpandedHUDSize() throws {
        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "expandedHUDSize")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded.expandedHUDSize, .standard)
    }

    func testExpandedHUDSizePresetsUseStableGeometry() {
        XCTAssertEqual(ExpandedHUDSize.compact.sideLength, 320)
        XCTAssertEqual(ExpandedHUDSize.standard.sideLength, 384)
        XCTAssertEqual(ExpandedHUDSize.large.sideLength, 448)
        XCTAssertEqual(ExpandedHUDSize.extraLarge.sideLength, 512)
        XCTAssertEqual(ExpandedHUDSize.standard.scale, 1)
    }

    func testAgentLightingAnimationIsOptInForDefaultsAndLegacySettings() throws {
        XCTAssertFalse(AppConfiguration.default.animatedAgentLighting)

        let currentData = try JSONEncoder().encode(AppConfiguration.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "animatedAgentLighting")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)

        XCTAssertFalse(decoded.animatedAgentLighting)
    }

    func testLayerAutoExitTimeoutIntervals() {
        XCTAssertEqual(LayerAutoExitTimeout.twoSeconds.interval, 2)
        XCTAssertEqual(LayerAutoExitTimeout.threeSeconds.interval, 3)
        XCTAssertEqual(LayerAutoExitTimeout.fourSeconds.interval, 4)
        XCTAssertEqual(LayerAutoExitTimeout.fiveSeconds.interval, 5)
        XCTAssertNil(LayerAutoExitTimeout.never.interval)
    }

    func testAgentTapTrackerFocusesMatchingAgentOnDoubleTap() {
        var tracker = AgentTapTracker()

        XCTAssertFalse(
            tracker.shouldFocusCodex(
                for: .agent3,
                threadKey: "thread-r",
                timestamp: 10,
                focusOnSingleTap: false
            )
        )
        XCTAssertTrue(
            tracker.shouldFocusCodex(
                for: .agent3,
                threadKey: "thread-r",
                timestamp: 10.3,
                focusOnSingleTap: false
            )
        )
    }

    func testAgentTapTrackerDoesNotFocusDifferentOrExpiredTap() {
        var tracker = AgentTapTracker()

        XCTAssertFalse(
            tracker.shouldFocusCodex(
                for: .agent3,
                threadKey: "thread-r",
                timestamp: 10,
                focusOnSingleTap: false
            )
        )
        XCTAssertFalse(
            tracker.shouldFocusCodex(
                for: .agent2,
                threadKey: "thread-e",
                timestamp: 10.2,
                focusOnSingleTap: false
            )
        )
        XCTAssertFalse(
            tracker.shouldFocusCodex(
                for: .agent2,
                threadKey: "thread-e",
                timestamp: 10.7,
                focusOnSingleTap: false
            )
        )
    }

    func testAgentTapTrackerHonorsOfficialSingleTapSetting() {
        var tracker = AgentTapTracker()

        XCTAssertTrue(
            tracker.shouldFocusCodex(
                for: .agent3,
                threadKey: "thread-r",
                timestamp: 10,
                focusOnSingleTap: true
            )
        )
    }

    func testCodexLayoutDecodesOfficialKeycaps() throws {
        let json = #"""
        {
          "version": 1,
          "slots": {
            "ACT06": {"keycapId":"TERM"},
            "ACT07": {"keycapId":"APPR"},
            "ACT08": {"keycapId":"REJ"},
            "ACT09": {"keycapId":"SPLIT"},
            "ACT10": {"keycapId":"BUG"},
            "ACT11": {"keycapId":"BRCH"},
            "ACT10_ACT11": {"keycapId":"MIC"},
            "ACT12": {"keycapId":"CODEX"}
          },
          "encoderMode": "reasoning",
          "voiceButtonMode": "realtime",
          "separateMicrophoneKeys": true,
          "agentSource": "pinned",
          "singleTapAgentKeys": true
        }
        """#

        let layout = try JSONDecoder().decode(
            CodexMicroLayoutSnapshot.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(layout.keycap(for: .fastMode), .terminal)
        XCTAssertEqual(layout.keycap(for: .fork), .fork)
        XCTAssertEqual(layout.keycap(for: .pushToTalk), .bug)
        XCTAssertEqual(layout.keycap(for: .pushToTalkSecondary), .draft)
        XCTAssertEqual(layout.encoderModeTitle, "Reasoning effort")
        XCTAssertEqual(layout.voiceButtonModeTitle, "Realtime voice")
        XCTAssertEqual(layout.agentSourceTitle, "Pinned tasks")
        XCTAssertTrue(layout.singleTapAgentKeys)
    }

    func testCombinedMicrophoneUsesTheOfficialDoubleSlot() {
        let layout = CodexMicroLayoutSnapshot.codexDefault

        XCTAssertFalse(layout.separateMicrophoneKeys)
        XCTAssertEqual(layout.keycap(for: .pushToTalk), .microphoneDouble)
    }

    func testEveryOfficialCodexKeycapIDHasAnAppearance() {
        let ids = [
            "FAST", "APPR", "REJ", "SPLIT", "MIC", "MIC1", "CODEX",
            "BUG", "OAI", "TERM", "DWN", "DEL", "NEW", "NAV", "MAGIC",
            "DIFF", "PLAY", "GIT", "BRCH", "BRANCH", "MRG", "PR", "PAINT",
            "LAB", "PARTY", "TIME", "MIND+", "MIND-", "EMPT1", "EMPT2",
            "EMPT3", "EMPT4", "EMPT5", "SETUP", "FOLD", "UPL", "APPS",
            "YOLO", "YEET",
        ]

        let appearances = ids.compactMap(MicroKeycap.init(codexID:))
        XCTAssertEqual(appearances.count, ids.count)
        XCTAssertEqual(Set(appearances).count, ids.count)
        XCTAssertEqual(MicroKeycap(codexID: "MIC")?.label, "MIC")
        XCTAssertEqual(MicroKeycap(codexID: "MIC1")?.label, "MIC1")
        XCTAssertEqual(MicroKeycap(codexID: "EMPT1")?.label, "EMPT1")
        XCTAssertEqual(MicroKeycap(codexID: "EMPT2")?.label, "EMPT2")
        XCTAssertEqual(MicroKeycap(codexID: "EMPT3")?.label, "EMPT3")
        XCTAssertEqual(MicroKeycap(codexID: "EMPT4")?.label, "EMPT4")
        XCTAssertEqual(MicroKeycap(codexID: "EMPT5")?.label, "EMPT5")
    }

    func testSecondMicrophoneSwitchUsesACT11AndStartsUnassigned() {
        XCTAssertEqual(MicroControl.pushToTalkSecondary.microKey, "ACT11")
        XCTAssertNil(
            KeyBinding.defaults
                .first(where: { $0.control == .pushToTalkSecondary })?
                .physicalKey
        )
    }

    func testAgentLightingUsesCodexMicroRGBValues() {
        XCTAssertEqual(AgentLightStatus.off.packedRGB, 0x000000)
        XCTAssertEqual(AgentLightStatus.idle.packedRGB, 0xFFFFFF)
        XCTAssertEqual(AgentLightStatus.working.packedRGB, 0x304FFE)
        XCTAssertEqual(AgentLightStatus.unread.packedRGB, 0x00FF4C)
        XCTAssertEqual(AgentLightStatus.awaitingApproval.packedRGB, 0xFF6D00)
        XCTAssertEqual(AgentLightStatus.awaitingResponse.packedRGB, 0xFF6D00)
        XCTAssertEqual(AgentLightStatus.error.packedRGB, 0xFF0033)
    }

    func testRendererLightingSnapshotDecodesAllAgentStates() throws {
        let json = #"""
        {
          "brightness": 0.8,
          "inactivityTimeoutMs": 180000,
          "slots": [
            {"id":0,"title":"Idle","threadKey":"local:0","status":"idle","selected":false},
            {"id":1,"title":"Work","threadKey":"local:1","status":"working","selected":true},
            {"id":2,"title":"Done","threadKey":"local:2","status":"unread","selected":false},
            {"id":3,"title":"Approve","threadKey":"local:3","status":"awaiting-approval","selected":false},
            {"id":4,"title":"Reply","threadKey":"local:4","status":"awaiting-response","selected":false},
            {"id":5,"title":"Failed","threadKey":"local:5","status":"error","selected":false}
          ]
        }
        """#

        let snapshot = try JSONDecoder().decode(
            CodexLightingSnapshot.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(snapshot.brightness, 0.8)
        XCTAssertEqual(snapshot.inactivityInterval, 180)
        XCTAssertEqual(snapshot.slots.map(\.status), [
            .idle,
            .working,
            .unread,
            .awaitingApproval,
            .awaitingResponse,
            .error,
        ])
        XCTAssertTrue(snapshot.light(for: 1).selected)
        XCTAssertEqual(snapshot.light(for: 1).threadKey, "local:1")
    }

    func testCodexLightingCanDisableInactivityDimming() {
        let snapshot = CodexLightingSnapshot(
            brightness: 1,
            inactivityTimeoutMs: 0,
            slots: []
        )

        XCTAssertNil(snapshot.inactivityInterval)
    }

    func testMissingAgentSlotFallsBackToUnassignedLight() {
        let light = CodexLightingSnapshot.off.light(for: 9)

        XCTAssertEqual(light.id, 9)
        XCTAssertEqual(light.status, .off)
        XCTAssertFalse(light.selected)
    }

    func testLightingSnapshotReturnsAssignedAndEmptySlots() throws {
        let snapshot = CodexLightingSnapshot(
            brightness: 1,
            inactivityTimeoutMs: 180_000,
            slots: [
                AgentLightState(id: 0, title: "One", threadKey: "local:0", status: .idle, selected: true),
                AgentLightState(id: 1, title: "Two", threadKey: "local:1", status: .idle, selected: false),
                AgentLightState(id: 2, title: "Three", threadKey: "local:2", status: .working, selected: false),
                AgentLightState(id: 3, title: "Four", threadKey: "local:3", status: .unread, selected: false),
                AgentLightState(id: 4, title: nil, threadKey: nil, status: .off, selected: false),
                AgentLightState(id: 5, title: nil, threadKey: nil, status: .off, selected: false),
            ]
        )

        XCTAssertEqual(snapshot.light(for: 0).title, "One")
        XCTAssertEqual(snapshot.light(for: 3).title, "Four")
        XCTAssertEqual(snapshot.light(for: 4).status, .off)
    }

    func testVirtualStickAndKnobUseCodexHardwareEventContract() throws {
        XCTAssertEqual(try XCTUnwrap(MicroControl.stickRight.codexJoystickAngle), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MicroControl.stickDown.codexJoystickAngle), 0.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MicroControl.stickLeft.codexJoystickAngle), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MicroControl.stickUp.codexJoystickAngle), 0.75, accuracy: 0.001)
        XCTAssertEqual(MicroControl.dialPrevious.codexEncoderKey, "ENC_CW")
        XCTAssertEqual(MicroControl.dialNext.codexEncoderKey, "ENC_CC")
        XCTAssertEqual(MicroControl.dialPress.codexEncoderKey, "ENC_PRESS")
    }

    func testEveryCommandKeyUsesItsOfficialCodexSlot() throws {
        let expectedKeys: [(MicroControl, String)] = [
            (.fastMode, "ACT06"),
            (.approve, "ACT07"),
            (.reject, "ACT08"),
            (.fork, "ACT09"),
            (.pushToTalk, "ACT10"),
            (.pushToTalkSecondary, "ACT11"),
            (.submit, "ACT12"),
        ]

        for (control, expectedKey) in expectedKeys {
            let outbound = CodexMicroBridge.outboundEvent(
                for: control,
                action: 1,
                lightingSnapshot: .off
            )
            guard case .key(let event) = outbound else {
                return XCTFail("\(control) did not create a Codex HID event")
            }
            XCTAssertEqual(event.key, expectedKey)
            XCTAssertEqual(event.act, 1)
            XCTAssertNil(event.slot)
            XCTAssertNil(event.threadKey)
        }
    }

    func testAgentKeysCarryTheirOfficialSlotAndThread() throws {
        let snapshot = CodexLightingSnapshot(
            brightness: 1,
            inactivityTimeoutMs: 180_000,
            slots: [
                AgentLightState(
                    id: 0,
                    title: "Task",
                    threadKey: "local:task-0",
                    status: .idle,
                    selected: true
                )
            ]
        )

        let outbound = CodexMicroBridge.outboundEvent(
            for: .agent0,
            action: 1,
            lightingSnapshot: snapshot
        )
        guard case .key(let event) = outbound else {
            return XCTFail("Agent key did not create a Codex HID event")
        }
        XCTAssertEqual(event.key, "AG00")
        XCTAssertEqual(event.act, 1)
        XCTAssertEqual(event.slot, 0)
        XCTAssertEqual(event.threadKey, "local:task-0")
    }

    func testDialAndStickProduceOfficialCodexPayloads() {
        XCTAssertEqual(
            CodexMicroBridge.outboundEvent(
                for: .dialPrevious,
                action: 1,
                lightingSnapshot: .off
            ),
            .key(CodexMicroKeyEvent(key: "ENC_CW", act: 2, agent: nil, slot: nil, threadKey: nil))
        )
        XCTAssertEqual(
            CodexMicroBridge.outboundEvent(
                for: .dialNext,
                action: 1,
                lightingSnapshot: .off
            ),
            .key(CodexMicroKeyEvent(key: "ENC_CC", act: 2, agent: nil, slot: nil, threadKey: nil))
        )
        XCTAssertNil(
            CodexMicroBridge.outboundEvent(
                for: .dialNext,
                action: 0,
                lightingSnapshot: .off
            )
        )
        XCTAssertEqual(
            CodexMicroBridge.outboundEvent(
                for: .dialPress,
                action: 1,
                lightingSnapshot: .off
            ),
            .key(CodexMicroKeyEvent(key: "ENC_PRESS", act: 1, agent: nil, slot: nil, threadKey: nil))
        )
        XCTAssertEqual(
            CodexMicroBridge.outboundEvent(
                for: .stickUp,
                action: 1,
                lightingSnapshot: .off
            ),
            .joystick(CodexMicroJoystickEvent(angle: 0.75, distance: 1))
        )
        XCTAssertEqual(
            CodexMicroBridge.outboundEvent(
                for: .stickUp,
                action: 0,
                lightingSnapshot: .off
            ),
            .joystick(CodexMicroJoystickEvent(angle: 0, distance: 0))
        )
    }

    func testLiveBridgeReceivesOfficialCodexState() async throws {
        let liveTestRequested = ProcessInfo.processInfo.environment["KEYSWITCH_LIVE_CODEX_TEST"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/keyswitch-live-codex-test")
        guard liveTestRequested else {
            throw XCTSkip("Set KEYSWITCH_LIVE_CODEX_TEST=1 when an isolated Codex renderer is on port 9348")
        }

        let connected = expectation(description: "Bridge connected")
        let receivedCodexLayout = expectation(description: "Official Codex layout received")
        let bridge = CodexMicroBridge(debugPort: 9348)
        var didReceiveLayout = false

        bridge.onStatusChange = { status in
            if status == .connected {
                connected.fulfill()
            }
        }
        bridge.onLayoutChange = { layout in
            guard !didReceiveLayout else { return }
            didReceiveLayout = true
            XCTAssertNotNil(layout.slots["ACT06"])
            XCTAssertNotNil(layout.slots["ACT12"])
            XCTAssertTrue(["recent", "pinned", "priority", "custom"].contains(layout.agentSource))
            receivedCodexLayout.fulfill()
        }

        bridge.connect()
        await fulfillment(
            of: [connected, receivedCodexLayout],
            timeout: 8
        )
        bridge.disconnect()
    }

    func testLiveBridgeRoundTripsOfficialSingleTapSetting() async throws {
        let liveTestRequested = ProcessInfo.processInfo.environment["KEYSWITCH_LIVE_CODEX_TEST"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/keyswitch-live-codex-test")
        guard liveTestRequested else {
            throw XCTSkip("Set KEYSWITCH_LIVE_CODEX_TEST=1 when an isolated Codex renderer is on port 9348")
        }

        let changed = expectation(description: "Official single-tap setting changed")
        let restored = expectation(description: "Official single-tap setting restored")
        let bridge = CodexMicroBridge(debugPort: 9348)
        var originalValue: Bool?
        var didObserveChange = false

        bridge.onLayoutChange = { layout in
            guard let originalValue else {
                originalValue = layout.singleTapAgentKeys
                bridge.setSingleTapAgentKeys(!layout.singleTapAgentKeys)
                return
            }

            if !didObserveChange, layout.singleTapAgentKeys != originalValue {
                didObserveChange = true
                changed.fulfill()
                bridge.setSingleTapAgentKeys(originalValue)
            } else if didObserveChange, layout.singleTapAgentKeys == originalValue {
                restored.fulfill()
            }
        }

        bridge.connect()
        await fulfillment(of: [changed, restored], timeout: 8)
        bridge.disconnect()
    }

    private func makeEngine(
        mode: ActivationMode,
        blockUnmapped: Bool,
        shortcut: ActivationShortcut = .standard
    ) -> KeyboardEngine {
        KeyboardEngine(
            configuration: KeyboardEngineConfiguration(
                activationMode: mode,
                activationShortcut: shortcut,
                blockUnmappedKeys: blockUnmapped,
                bindings: KeyBinding.defaults
            ),
            captureEventTapIsReady: { _ in true }
        )
    }

    private func pressDefaultShortcut(on engine: KeyboardEngine) {
        _ = engine.handle(
            type: .flagsChanged,
            event: modifierEventUnchecked(code: 63, flags: .maskSecondaryFn)
        )
        _ = engine.handle(
            type: .flagsChanged,
            event: modifierEventUnchecked(
                code: 59,
                flags: [.maskSecondaryFn, .maskControl]
            )
        )
    }

    private func releaseDefaultShortcut(on engine: KeyboardEngine) {
        _ = engine.handle(
            type: .flagsChanged,
            event: modifierEventUnchecked(code: 59, flags: .maskSecondaryFn)
        )
        _ = engine.handle(
            type: .flagsChanged,
            event: modifierEventUnchecked(code: 63, flags: [])
        )
    }

    private func keyEvent(
        code: UInt16,
        isDown: Bool,
        flags: CGEventFlags = []
    ) throws -> CGEvent {
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: isDown)
        )
        event.flags = flags
        return event
    }

    private func modifierEvent(code: UInt16, flags: CGEventFlags) throws -> CGEvent {
        let event = try keyEvent(code: code, isDown: !flags.isEmpty)
        event.flags = flags
        return event
    }

    private func modifierEventUnchecked(code: UInt16, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(code),
            keyDown: !flags.isEmpty
        )!
        event.flags = flags
        return event
    }
}
