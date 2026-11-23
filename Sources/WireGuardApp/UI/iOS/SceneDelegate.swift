// SPDX-License-Identifier: MIT
// Copyright © 2026 WireGuard LLC. All Rights Reserved.

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let restorationActivityType = "com.wireguard.scene-state"
    private static let restoredTunnelNameKey = "selectedTunnelName"

    var window: UIWindow?
    private var mainVC: MainViewController?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        if !connectionOptions.urlContexts.isEmpty || connectionOptions.shortcutItem != nil {
            appDelegate?.isLaunchedForSpecificAction = true
        }

        let mainVC = MainViewController()
        self.mainVC = mainVC
        appDelegate?.mainVC = mainVC

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = mainVC
        self.window = window
        window.makeKeyAndVisible()

        if appDelegate?.isLaunchedForSpecificAction != true,
           let activity = session.stateRestorationActivity,
           activity.activityType == Self.restorationActivityType,
           let tunnelName = activity.userInfo?[Self.restoredTunnelNameKey] as? String,
           mainVC.tunnelNameForRestoration() != tunnelName {
            mainVC.showTunnelDetailForTunnel(named: tunnelName, animated: false, shouldToggleStatus: false)
        }

        for context in connectionOptions.urlContexts.sorted(by: { $0.url.absoluteString < $1.url.absoluteString }) {
            mainVC.importFromDisposableFile(url: context.url)
        }
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = mainVC.handleShortcutItem(shortcutItem)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts.sorted(by: { $0.url.absoluteString < $1.url.absoluteString }) {
            mainVC?.importFromDisposableFile(url: context.url)
        }
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
           appDelegate.mainVC === mainVC {
            appDelegate.mainVC = nil
        }
        mainVC = nil
        window = nil
    }
}
