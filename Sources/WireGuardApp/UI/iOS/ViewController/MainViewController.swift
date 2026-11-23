// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import UIKit

class MainViewController: UISplitViewController {

    var tunnelsManager: TunnelsManager?
    private var pendingTunnelsManagerActions: [(TunnelsManager) -> Void] = []
    var tunnelsListVC: TunnelsListTableViewController?

    init() {
        let detailVC = UIViewController()
        detailVC.view.backgroundColor = .systemBackground
        let detailNC = UINavigationController(rootViewController: detailVC)

        let masterVC = TunnelsListTableViewController()
        let masterNC = UINavigationController(rootViewController: masterVC)

        tunnelsListVC = masterVC

        super.init(nibName: nil, bundle: nil)

        viewControllers = [ masterNC, detailNC ]

        restorationIdentifier = "MainVC"
        masterNC.restorationIdentifier = "MasterNC"
        detailNC.restorationIdentifier = "DetailNC"
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        delegate = self

        // On iPad, always show both masterVC and detailVC, even in portrait mode, like the Settings app
        preferredDisplayMode = .allVisible

        // Create the tunnels manager, and when it's ready, inform tunnelsListVC
        TunnelsManager.create { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                ErrorPresenter.showErrorAlert(error: error, from: self)
            case .success(let tunnelsManager):
                self.tunnelsManager = tunnelsManager
                self.tunnelsListVC?.setTunnelsManager(tunnelsManager: tunnelsManager)

                tunnelsManager.activationDelegate = self

                self.pendingTunnelsManagerActions.forEach { $0(tunnelsManager) }
                self.pendingTunnelsManagerActions.removeAll()
            }
        }
    }

    func allTunnelNames() -> [String]? {
        guard let tunnelsManager = self.tunnelsManager else { return nil }
        return tunnelsManager.mapTunnels { $0.name }
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == QuickActionItem.type else { return false }
        showTunnelDetailForTunnel(named: shortcutItem.localizedTitle, animated: false, shouldToggleStatus: true)
        return true
    }

    func tunnelNameForRestoration() -> String? {
        for viewController in viewControllers {
            guard let navigationController = viewController as? UINavigationController else { continue }
            if let detailViewController = navigationController.viewControllers.reversed().compactMap({ $0 as? TunnelDetailTableViewController }).first {
                return detailViewController.tunnel.name
            }
        }
        return nil
    }
}

extension MainViewController: TunnelsManagerActivationDelegate {
    func tunnelActivationAttemptFailed(tunnel: TunnelContainer, error: TunnelsManagerActivationAttemptError) {
        ErrorPresenter.showErrorAlert(error: error, from: self)
    }

    func tunnelActivationAttemptSucceeded(tunnel: TunnelContainer) {
        // Nothing to do
    }

    func tunnelActivationFailed(tunnel: TunnelContainer, error: TunnelsManagerActivationError) {
        ErrorPresenter.showErrorAlert(error: error, from: self)
    }

    func tunnelActivationSucceeded(tunnel: TunnelContainer) {
        // Nothing to do
    }
}

extension MainViewController {
    private func performWhenTunnelsManagerReady(_ action: @escaping (TunnelsManager) -> Void) {
        if let tunnelsManager = tunnelsManager {
            action(tunnelsManager)
        } else {
            pendingTunnelsManagerActions.append(action)
        }
    }

    func refreshTunnelConnectionStatuses() {
        if let tunnelsManager = tunnelsManager {
            tunnelsManager.refreshStatuses()
        }
    }

    func showTunnelDetailForTunnel(named tunnelName: String, animated: Bool, shouldToggleStatus: Bool) {
        performWhenTunnelsManagerReady { [weak self] tunnelsManager in
            guard let self = self, let tunnelsListVC = self.tunnelsListVC else { return }
            if let tunnel = tunnelsManager.tunnel(named: tunnelName) {
                tunnelsListVC.showTunnelDetail(for: tunnel, animated: false)
                if shouldToggleStatus {
                    if tunnel.status == .inactive {
                        tunnelsManager.startActivation(of: tunnel)
                    } else if tunnel.status == .active {
                        tunnelsManager.startDeactivation(of: tunnel)
                    }
                }
            }
        }
    }

    func importFromDisposableFile(url: URL) {
        performWhenTunnelsManagerReady { [weak self] tunnelsManager in
            TunnelImporter.importFromFile(urls: [url], into: tunnelsManager, sourceVC: self, errorPresenterType: ErrorPresenter.self) {
                _ = FileManager.deleteFile(at: url)
            }
        }
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        // On iPhone, if the secondaryVC (detailVC) is just a UIViewController, it indicates that it's empty,
        // so just show the primaryVC (masterVC).
        let detailVC = (secondaryViewController as? UINavigationController)?.viewControllers.first
        let isDetailVCEmpty: Bool
        if let detailVC = detailVC {
            isDetailVCEmpty = (type(of: detailVC) == UIViewController.self)
        } else {
            isDetailVCEmpty = true
        }
        return isDetailVCEmpty
    }
}
