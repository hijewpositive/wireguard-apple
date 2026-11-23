// SPDX-License-Identifier: MIT
// Copyright © 2026 WireGuard LLC. All Rights Reserved.

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let restorationActivityType = "com.wireguard.scene-state"
    private static let restoredTunnelNameKey = "selectedTunnelName"

    var window: UIWindow?
    private var mainVC: MainViewController?
    private var launchActionState = SceneLaunchActionState()

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        launchActionState.update(
            hasURLContexts: !connectionOptions.urlContexts.isEmpty,
            hasShortcutItem: connectionOptions.shortcutItem != nil
        )
        guard let windowScene = scene as? UIWindowScene else { return }

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        let mainVC = MainViewController()
        self.mainVC = mainVC
        appDelegate?.mainVC = mainVC

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = mainVC
        self.window = window
        window.makeKeyAndVisible()

        if !launchActionState.isLaunchedForSpecificAction,
           let activity = session.stateRestorationActivity,
           activity.activityType == Self.restorationActivityType,
           let tunnelName = activity.userInfo?[Self.restoredTunnelNameKey] as? String,
           mainVC.tunnelNameForRestoration() != tunnelName {
            mainVC.showTunnelDetailForTunnel(named: tunnelName, animated: false, shouldToggleStatus: false)
        }

        let importURLs = connectionOptions.urlContexts
            .sorted(by: { $0.url.absoluteString < $1.url.absoluteString })
            .map { $0.url }
        appDelegate?.enqueueDisposableFileImports(importURLs)
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = mainVC.handleShortcutItem(shortcutItem)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let importURLs = URLContexts
            .sorted(by: { $0.url.absoluteString < $1.url.absoluteString })
            .map { $0.url }
        (UIApplication.shared.delegate as? AppDelegate)?.enqueueDisposableFileImports(importURLs)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        mainVC?.refreshTunnelConnectionStatuses()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        let activity = NSUserActivity(activityType: Self.restorationActivityType)
        if let tunnelName = mainVC?.tunnelNameForRestoration() {
            activity.addUserInfoEntries(from: [Self.restoredTunnelNameKey: tunnelName])
        }
        return activity
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard let allTunnelNames = mainVC?.allTunnelNames() else { return }
        UIApplication.shared.shortcutItems = QuickActionItem.createItems(allTunnelNames: allTunnelNames)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(mainVC?.handleShortcutItem(shortcutItem) ?? false)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let mainVC = mainVC,
           appDelegate.mainVC === mainVC {
            appDelegate.clearDisposableFileImportHandler(for: mainVC)
            appDelegate.mainVC = nil
        }
        mainVC = nil
        window = nil
    }
}
