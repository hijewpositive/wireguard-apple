// SPDX-License-Identifier: MIT
// Copyright © 2026 WireGuard LLC. All Rights Reserved.

import Foundation

/// Serializes disposable configuration imports independently of any scene's lifetime.
final class SceneImportQueue {
    typealias Importer = (URL, @escaping () -> Void) -> Void

    private var pendingURLs: [URL] = []
    private var importer: Importer?
    private var activeImportID: UUID?
    private let cleanup: (URL) -> Void

    init(cleanup: @escaping (URL) -> Void) {
        self.cleanup = cleanup
    }

    func enqueue(_ url: URL) {
        requireMainThread()
        pendingURLs.append(url)
        processNextIfReady()
    }

    func setImporter(_ importer: Importer?) {
        requireMainThread()
        self.importer = importer
        processNextIfReady()
    }

    private func processNextIfReady() {
        requireMainThread()
        guard activeImportID == nil, let url = pendingURLs.first, let importer = importer else { return }

        pendingURLs.removeFirst()
        let importID = UUID()
        activeImportID = importID
        importer(url) { [weak self] in
            guard let self = self else { return }
            self.requireMainThread()
            guard self.activeImportID == importID else { return }

            self.cleanup(url)
            self.activeImportID = nil
            self.processNextIfReady()
        }
    }

    private func requireMainThread() {
        precondition(Thread.isMainThread, "SceneImportQueue must be used on the main thread")
    }
}
