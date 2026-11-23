import Foundation

@main
private struct SceneBehaviorTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("expected a task-owned temporary directory")
        }
        let temporaryDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try testImportFailureWaitsForLivePresentationAndAcknowledgement(in: temporaryDirectory)
        try testSuccessfulImportsCleanUpAndContinueInFIFOOrder(in: temporaryDirectory)
        try testReplacementSceneOwnsQueueBeforeItsManagerIsReady(in: temporaryDirectory)
        testSceneActionStateResetsForEachConnection()
        testNestedCollapsedAndWideNavigationRestoreSelectedTunnel()
        testEmptyNavigationDoesNotRestoreATunnel()
        print("PASS: import failures wait for a live presenter and dismissal")
        print("PASS: successful imports clean up and proceed in FIFO order")
        print("PASS: replacement scene owns imports across the manager-readiness gap")
        print("PASS: scene action state resets on reconnection")
        print("PASS: nested compact and wide details restore selection")
        print("PASS: empty navigation restores no tunnel")
    }

    private static func testImportFailureWaitsForLivePresentationAndAcknowledgement(in directory: URL) throws {
        let firstURL = directory.appendingPathComponent("first-import.conf")
        let secondURL = directory.appendingPathComponent("second-import.conf")
        let fixture = Data("synthetic-config-fixture-without-key-material".utf8)
        try fixture.write(to: firstURL, options: .atomic)
        try fixture.write(to: secondURL, options: .atomic)

        let queue = SceneImportQueue { url in
            try? FileManager.default.removeItem(at: url)
        }
        let firstScene = NSObject()
        let reconnectedScene = NSObject()
        let replacementScene = NSObject()
        queue.claimOwnership(for: firstScene)
        queue.enqueue(firstURL)
        queue.enqueue(secondURL)
        check(FileManager.default.fileExists(atPath: firstURL.path), "queued file was removed before processing")

        var started: [URL] = []
        var completions: [(SceneImportQueue.ImportResult) -> Void] = []
        queue.setImporter({ url, completion in
            started.append(url)
            completions.append(completion)
        }, for: firstScene)
        check(started == [firstURL], "only the first import should start")

        // Match SceneDelegate.sceneDidDisconnect: detach both scene-bound callbacks.
        queue.clearOwnership(for: firstScene)
        completions[0](.failure(title: "Import failed", message: "Synthetic failure"))
        check(started == [firstURL], "the second import started without a ready scene manager")
        check(FileManager.default.fileExists(atPath: firstURL.path), "failed import was deleted before its error was shown")
        check(FileManager.default.fileExists(atPath: secondURL.path), "pending import file was cleaned up too early")
        check(completions.count == 1, "a queued import started after its scene detached")

        var presentedBy: [String] = []
        var dismissals: [() -> Void] = []
        queue.claimOwnership(for: reconnectedScene)
        queue.setErrorPresenter({ title, message, onDismissal in
            check(title == "Import failed" && message == "Synthetic failure", "failure details changed while queued")
            presentedBy.append("reconnected-scene")
            dismissals.append(onDismissal)
        }, for: reconnectedScene)
        queue.setImporter({ url, completion in
            started.append(url)
            completions.append(completion)
        }, for: reconnectedScene)
        check(presentedBy == ["reconnected-scene"], "failure was not presented in the live scene")
        check(FileManager.default.fileExists(atPath: firstURL.path), "failed import was cleaned before dismissal")
        check(started == [firstURL], "the next import overlapped the unacknowledged error")

        // A disconnect invalidates the old alert's acknowledgement. Reconnection
        // must re-present the same failure rather than lose or prematurely clean it.
        queue.clearOwnership(for: reconnectedScene)
        dismissals[0]()
        check(FileManager.default.fileExists(atPath: firstURL.path), "stale alert dismissal cleaned the import")
        check(started == [firstURL], "stale alert dismissal advanced the import queue")

        queue.claimOwnership(for: replacementScene)
        queue.setErrorPresenter({ title, _, onDismissal in
            presentedBy.append("replacement-scene")
            dismissals.append(onDismissal)
        }, for: replacementScene)
        queue.setImporter({ url, completion in
            started.append(url)
            completions.append(completion)
        }, for: replacementScene)
        check(presentedBy == ["reconnected-scene", "replacement-scene"], "pending failure was not rebound to the new scene")
        dismissals[1]()
        check(!FileManager.default.fileExists(atPath: firstURL.path), "acknowledged failure file was not cleaned up")
        check(started == [firstURL, secondURL], "queued import did not start after acknowledgement")

        completions[1](.failure(title: "Second failure", message: "Synthetic second failure"))
        check(presentedBy.count == 3, "second import error was not presented")
        check(started == [firstURL, secondURL], "an import was started more than once")
        check(FileManager.default.fileExists(atPath: secondURL.path), "second failed import was deleted before acknowledgement")
        dismissals[2]()
        check(!FileManager.default.fileExists(atPath: secondURL.path), "second acknowledged failure file was not cleaned up")
    }

    private static func testSuccessfulImportsCleanUpAndContinueInFIFOOrder(in directory: URL) throws {
        let firstURL = directory.appendingPathComponent("successful-first.conf")
        let secondURL = directory.appendingPathComponent("successful-second.conf")
        let fixture = Data("synthetic-success-fixture-without-key-material".utf8)
        try fixture.write(to: firstURL, options: .atomic)
        try fixture.write(to: secondURL, options: .atomic)

        let queue = SceneImportQueue { url in
            try? FileManager.default.removeItem(at: url)
        }
        let scene = NSObject()
        var started: [URL] = []
        var completions: [(SceneImportQueue.ImportResult) -> Void] = []
        queue.enqueue(firstURL)
        queue.enqueue(secondURL)
        queue.claimOwnership(for: scene)
        queue.setImporter({ url, completion in
            started.append(url)
            completions.append(completion)
        }, for: scene)
        check(started == [firstURL], "successful imports did not start in FIFO order")

        completions[0](.success)
        check(!FileManager.default.fileExists(atPath: firstURL.path), "successful import file was not cleaned up")
        check(started == [firstURL, secondURL], "next import did not start after success")
        completions[0](.failure(title: "stale", message: "stale callback"))
        check(FileManager.default.fileExists(atPath: secondURL.path), "stale result removed the active import")
        check(started == [firstURL, secondURL], "stale result started another import")

        completions[1](.success)
        check(!FileManager.default.fileExists(atPath: secondURL.path), "second successful import file was not cleaned up")
        check(started == [firstURL, secondURL], "an import was started more than once")
    }

    private static func testReplacementSceneOwnsQueueBeforeItsManagerIsReady(in directory: URL) throws {
        let activeURL = directory.appendingPathComponent("active-before-replacement.conf")
        let queuedURL = directory.appendingPathComponent("queued-during-replacement.conf")
        let fixture = Data("synthetic-scene-handoff-fixture-without-key-material".utf8)
        try fixture.write(to: activeURL, options: .atomic)
        try fixture.write(to: queuedURL, options: .atomic)

        let queue = SceneImportQueue { url in
            try? FileManager.default.removeItem(at: url)
        }
        let sceneA = NSObject()
        let sceneB = NSObject()
        var startedByA: [URL] = []
        var startedByB: [URL] = []
        var completionFromA: ((SceneImportQueue.ImportResult) -> Void)?
        var completionFromB: ((SceneImportQueue.ImportResult) -> Void)?
        var presentedBy: [String] = []
        var dismissals: [() -> Void] = []

        queue.claimOwnership(for: sceneA)
        queue.setErrorPresenter({ _, _, onDismissal in
            presentedBy.append("scene-A")
            dismissals.append(onDismissal)
        }, for: sceneA)
        queue.setImporter({ url, completion in
            startedByA.append(url)
            completionFromA = completion
        }, for: sceneA)
        queue.enqueue(activeURL)
        check(startedByA == [activeURL], "scene A did not start its active import")

        // Scene B becomes the owner immediately, before its manager is ready.
        // Scene A's later disconnect must not detach B or restore A's handlers.
        queue.claimOwnership(for: sceneB)
        queue.setErrorPresenter({ _, _, _ in
            presentedBy.append("stale-scene-A")
        }, for: sceneA)
        queue.setImporter({ url, _ in
            startedByA.append(url)
        }, for: sceneA)
        queue.clearOwnership(for: sceneA)
        queue.enqueue(queuedURL)
        completionFromA?(.failure(title: "Import failed", message: "Failure during handoff"))
        check(startedByA == [activeURL], "scene A's importer handled a URL after ownership moved")
        check(startedByB.isEmpty, "scene B imported before its manager was ready")
        check(presentedBy.isEmpty, "failure was presented without a live scene handler")
        check(FileManager.default.fileExists(atPath: activeURL.path), "active failed input was lost during handoff")
        check(FileManager.default.fileExists(atPath: queuedURL.path), "queued input was cleaned during handoff")

        queue.setErrorPresenter({ title, message, onDismissal in
            check(title == "Import failed" && message == "Failure during handoff",
                  "failure details were lost while scene B initialized")
            presentedBy.append("scene-B")
            dismissals.append(onDismissal)
        }, for: sceneB)
        queue.setImporter({ url, completion in
            startedByB.append(url)
            completionFromB = completion
        }, for: sceneB)
        check(presentedBy == ["scene-B"], "scene B did not receive the retained failure")
        check(startedByB.isEmpty, "queued import overlapped an unacknowledged failure")

        dismissals[0]()
        check(!FileManager.default.fileExists(atPath: activeURL.path), "acknowledged active input was not cleaned")
        check(startedByB == [queuedURL], "queued input did not resume with scene B's manager")

        // A duplicate/late result from A cannot complete B's now-active import.
        completionFromA?(.success)
        check(FileManager.default.fileExists(atPath: queuedURL.path), "stale scene-A completion removed scene B's input")
        check(startedByB == [queuedURL], "stale scene-A completion advanced scene B's queue")
        completionFromB?(.success)
        check(!FileManager.default.fileExists(atPath: queuedURL.path), "scene B's successful input was not cleaned")
    }

    private static func testSceneActionStateResetsForEachConnection() {
        var state = SceneLaunchActionState()
        state.update(hasURLContexts: true, hasShortcutItem: false)
        check(state.isLaunchedForSpecificAction, "URL launch did not suppress restoration for its scene")
        state.update(hasURLContexts: false, hasShortcutItem: false)
        check(!state.isLaunchedForSpecificAction, "normal scene reconnection inherited an earlier URL action")
        state.update(hasURLContexts: false, hasShortcutItem: true)
        check(state.isLaunchedForSpecificAction, "shortcut launch did not suppress restoration for its scene")
        state.update(hasURLContexts: false, hasShortcutItem: false)
        check(!state.isLaunchedForSpecificAction, "normal reconnection inherited an earlier shortcut action")
    }

    private static func testNestedCollapsedAndWideNavigationRestoreSelectedTunnel() {
        let selectedDetail = TunnelDetailRestoration.Node(tunnelName: "selected", children: [])
        let detailNavigation = TunnelDetailRestoration.Node(tunnelName: nil, children: [selectedDetail])
        let masterNavigation = TunnelDetailRestoration.Node(
            tunnelName: nil,
            children: [
                TunnelDetailRestoration.Node(tunnelName: nil, children: []),
                detailNavigation
            ]
        )

        let collapsedHierarchy = [masterNavigation]
        check(TunnelDetailRestoration.tunnelName(in: collapsedHierarchy) == "selected",
              "nested compact detail was not restored")

        let wideHierarchy = [
            TunnelDetailRestoration.Node(tunnelName: nil, children: []),
            detailNavigation
        ]
        check(TunnelDetailRestoration.tunnelName(in: wideHierarchy) == "selected",
              "wide-layout detail was not restored")
    }

    private static func testEmptyNavigationDoesNotRestoreATunnel() {
        let emptyHierarchy = [
            TunnelDetailRestoration.Node(tunnelName: nil, children: [
                TunnelDetailRestoration.Node(tunnelName: nil, children: [])
            ])
        ]
        check(TunnelDetailRestoration.tunnelName(in: emptyHierarchy) == nil,
              "empty navigation produced a tunnel selection")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
