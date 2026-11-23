// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import UIKit
import os.log

private final class WeakImportSource {
    weak var viewController: UIViewController?

    init(_ viewController: UIViewController) {
        self.viewController = viewController
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    weak var mainVC: MainViewController?
    private lazy var disposableFileImportQueue = SceneImportQueue { url in
        _ = FileManager.deleteFile(at: url)
    }
    var isProcessLaunchedForSpecificAction = false

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.configureGlobal(tagged: "APP", withFilePath: FileManager.logFileURL?.path)

        if let launchOptions = launchOptions {
            if launchOptions[.url] != nil || launchOptions[.shortcutItem] != nil {
                isProcessLaunchedForSpecificAction = true
            }
        }

        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        handleOpenURL(url)
        return true
    }

    func handleOpenURL(_ url: URL) {
        enqueueDisposableFileImports([url])
    }

    func enqueueDisposableFileImports(_ urls: [URL]) {
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            disposableFileImportQueue.enqueue(url)
        }
    }

    func claimDisposableFileImportOwnership(for sourceVC: MainViewController) {
        disposableFileImportQueue.claimOwnership(for: sourceVC)
        mainVC = sourceVC
    }

    func setDisposableFileImportHandler(tunnelsManager: TunnelsManager, sourceVC: MainViewController) {
        // Manager creation is asynchronous; a disconnected scene must not reclaim the queue.
        guard mainVC === sourceVC else { return }

        let weakSource = WeakImportSource(sourceVC)
        disposableFileImportQueue.setErrorPresenter({ title, message, onDismissal in
            guard let sourceVC = weakSource.viewController else { return }
            ErrorPresenter.showErrorAlert(
                title: title,
                message: message,
                from: sourceVC,
                onDismissal: onDismissal
            )
        }, for: sourceVC)
        disposableFileImportQueue.setImporter({ url, completion in
            TunnelImporter.importFromFile(
                urls: [url],
                into: tunnelsManager,
                sourceVC: weakSource.viewController,
                errorPresenterType: ErrorPresenter.self,
                resultHandler: { failure in
                    if let failure = failure {
                        completion(.failure(title: failure.title, message: failure.message))
                    } else {
                        completion(.success)
                    }
                }
            )
        }, for: sourceVC)
    }

    func clearDisposableFileImportHandler(for sourceVC: MainViewController) {
        guard mainVC === sourceVC else { return }
        disposableFileImportQueue.clearOwnership(for: sourceVC)
        mainVC = nil
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == QuickActionItem.type else { return false }
        _ = mainVC?.handleShortcutItem(shortcutItem)
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handleShortcutItem(shortcutItem))
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        return true
    }

    func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        return !self.isProcessLaunchedForSpecificAction
    }

    func application(_ application: UIApplication, viewControllerWithRestorationIdentifierPath identifierComponents: [String], coder: NSCoder) -> UIViewController? {
        guard let vcIdentifier = identifierComponents.last else { return nil }
        if vcIdentifier.hasPrefix("TunnelDetailVC:") {
            let tunnelName = String(vcIdentifier.suffix(vcIdentifier.count - "TunnelDetailVC:".count))
            if let tunnelsManager = mainVC?.tunnelsManager {
                if let tunnel = tunnelsManager.tunnel(named: tunnelName) {
                    return TunnelDetailTableViewController(tunnelsManager: tunnelsManager, tunnel: tunnel)
                }
            } else {
                // Show it when tunnelsManager is available
                mainVC?.showTunnelDetailForTunnel(named: tunnelName, animated: false, shouldToggleStatus: false)
            }
        }
        return nil
    }
}
