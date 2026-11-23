// SPDX-License-Identifier: MIT
// Copyright © 2026 WireGuard LLC. All Rights Reserved.

import Foundation

/// Scene-local launch options must be recomputed for every scene connection.
struct SceneLaunchActionState {
    private(set) var isLaunchedForSpecificAction = false

    mutating func update(hasURLContexts: Bool, hasShortcutItem: Bool) {
        isLaunchedForSpecificAction = hasURLContexts || hasShortcutItem
    }
}

/// Serializes disposable imports while keeping failures until a live scene acknowledges them.
final class SceneImportQueue {
    enum ImportResult {
        case success
        case failure(title: String, message: String)
    }

    typealias Importer = (URL, @escaping (ImportResult) -> Void) -> Void
    typealias ErrorPresenter = (String, String, @escaping () -> Void) -> Void

    private var pendingURLs: [URL] = []
    private var importer: Importer?
    private var errorPresenter: ErrorPresenter?
    private var activeImportID: UUID?
    private var activeURL: URL?
    private var pendingFailure: (title: String, message: String)?
    private var activePresentationID: UUID?
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

    func setErrorPresenter(_ errorPresenter: ErrorPresenter?) {
        requireMainThread()
        self.errorPresenter = errorPresenter
        // A dismissal from a disconnected scene must not acknowledge this error.
        activePresentationID = nil
        presentPendingFailureIfPossible()
    }

    private func processNextIfReady() {
        requireMainThread()
        guard activeImportID == nil, let url = pendingURLs.first, let importer = importer else { return }

        pendingURLs.removeFirst()
        let importID = UUID()
        activeImportID = importID
        activeURL = url
        importer(url) { [weak self] result in
            guard let self = self else { return }
            self.requireMainThread()
            guard self.activeImportID == importID else { return }

            switch result {
            case .success:
                self.finishActiveImport(importID: importID, url: url)
            case .failure(let title, let message):
                self.pendingFailure = (title: title, message: message)
                self.presentPendingFailureIfPossible()
            }
        }
    }

    private func presentPendingFailureIfPossible() {
        requireMainThread()
        guard activePresentationID == nil,
              let importID = activeImportID,
              let url = activeURL,
              let failure = pendingFailure,
              let errorPresenter = errorPresenter else { return }

        let presentationID = UUID()
        activePresentationID = presentationID
        errorPresenter(failure.title, failure.message) { [weak self] in
            guard let self = self else { return }
            self.requireMainThread()
            guard self.activeImportID == importID,
                  self.activePresentationID == presentationID else { return }
            self.finishActiveImport(importID: importID, url: url)
        }
    }

    private func finishActiveImport(importID: UUID, url: URL) {
        requireMainThread()
        guard activeImportID == importID else { return }
        cleanup(url)
        activeImportID = nil
        activeURL = nil
        pendingFailure = nil
        activePresentationID = nil
        processNextIfReady()
    }

    private func requireMainThread() {
        precondition(Thread.isMainThread, "SceneImportQueue must be used on the main thread")
    }
}
