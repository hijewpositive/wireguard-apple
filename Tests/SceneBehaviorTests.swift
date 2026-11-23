import Foundation

@main
private struct SceneBehaviorTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("expected a task-owned temporary directory")
        }
        let temporaryDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try testQueuedImportsSurviveSceneReadinessChangesAndRunSerially(in: temporaryDirectory)
        testNestedCollapsedAndWideNavigationRestoreSelectedTunnel()
        testEmptyNavigationDoesNotRestoreATunnel()
        print("PASS: queued imports wait, serialize, and clean up")
        print("PASS: nested compact and wide details restore selection")
        print("PASS: empty navigation restores no tunnel")
    }

    private static func testQueuedImportsSurviveSceneReadinessChangesAndRunSerially(in directory: URL) throws {
        let firstURL = directory.appendingPathComponent("first-import.conf")
        let secondURL = directory.appendingPathComponent("second-import.conf")
        let fixture = Data("synthetic-config-fixture-without-key-material".utf8)
        try fixture.write(to: firstURL, options: .atomic)
        try fixture.write(to: secondURL, options: .atomic)

        let queue = SceneImportQueue { url in
            try? FileManager.default.removeItem(at: url)
        }
        queue.enqueue(firstURL)
        queue.enqueue(secondURL)
        check(FileManager.default.fileExists(atPath: firstURL.path), "queued file was removed before processing")

        var started: [URL] = []
        var completions: [() -> Void] = []
        queue.setImporter { url, completion in
            started.append(url)
            completions.append(completion)
        }
        check(started == [firstURL], "only the first import should start")

        // The scene disappears while the first manager-backed import is in flight.
        queue.setImporter(nil)
        completions[0]()
        check(started == [firstURL], "the second import started without a ready scene manager")
        check(!FileManager.default.fileExists(atPath: firstURL.path), "completed import file was not cleaned up")
        check(FileManager.default.fileExists(atPath: secondURL.path), "pending import file was cleaned up too early")

        queue.setImporter { url, completion in
            started.append(url)
            completions.append(completion)
        }
        check(started == [firstURL, secondURL], "queued import did not resume in FIFO order")
        completions[0]() // A duplicate callback must not complete the second import.
        check(FileManager.default.fileExists(atPath: secondURL.path), "stale completion removed the next import")
        check(started == [firstURL, secondURL], "stale completion started another import")

        completions[1]()
        check(!FileManager.default.fileExists(atPath: secondURL.path), "finished import file was not cleaned up")
        check(started == [firstURL, secondURL], "an import was started more than once")
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
