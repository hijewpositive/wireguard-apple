"""Structural regression checks for iOS scene lifecycle/adaptive split setup.

These checks complement simulator-hosted rendering; they do not replace it.
"""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "Sources/WireGuardApp/UI/iOS"


class SceneLifecycleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with (IOS / "Info.plist").open("rb") as file:
            cls.info = plistlib.load(file)
        cls.app_delegate = (IOS / "AppDelegate.swift").read_text()
        cls.scene_delegate = (IOS / "SceneDelegate.swift")
        cls.main_controller = (IOS / "ViewController/MainViewController.swift").read_text()

    def test_scene_manifest_selects_the_window_scene_delegate(self):
        manifest = self.info["UIApplicationSceneManifest"]
        self.assertFalse(manifest["UIApplicationSupportsMultipleScenes"])
        configurations = manifest["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"]
        self.assertEqual(len(configurations), 1)
        self.assertEqual(
            configurations[0]["UISceneDelegateClassName"],
            "$(PRODUCT_MODULE_NAME).SceneDelegate",
        )

    def test_cold_launch_routes_urls_and_shortcuts_before_restoration(self):
        source = self.scene_delegate.read_text()
        self.assertIn("connectionOptions.urlContexts", source)
        self.assertIn("connectionOptions.shortcutItem", source)
        self.assertIn("launchActionState.update", source)
        self.assertIn("if !launchActionState.isLaunchedForSpecificAction", source)
        self.assertNotIn("appDelegate?.isLaunchedForSpecificAction = true", source)
        self.assertIn("enqueueDisposableFileImports", source)
        self.assertNotIn("mainVC.importFromDisposableFile", source)

    def test_window_is_bound_to_the_connected_scene_not_screen_bounds(self):
        source = self.scene_delegate.read_text()
        self.assertIn("UIWindow(windowScene: windowScene)", source)
        self.assertNotIn("UIScreen.main.bounds", self.app_delegate)
        self.assertNotIn("UIWindow(frame:", self.app_delegate)

    def test_scene_forwards_import_urls_and_quick_actions(self):
        source = self.scene_delegate.read_text()
        self.assertIn("openURLContexts", source)
        self.assertIn("enqueueDisposableFileImports", source)
        self.assertNotIn("importFromDisposableFile", source)
        self.assertIn("performActionFor", source)
        self.assertIn("handleShortcutItem", source)

    def test_import_queue_is_owned_by_application_and_ready_after_manager_creation(self):
        app = self.app_delegate
        main = self.main_controller
        importer = (ROOT / "Sources/WireGuardApp/UI/TunnelImporter.swift").read_text()
        picker = (IOS / "ViewController/TunnelsListTableViewController.swift").read_text()
        self.assertIn("SceneImportQueue", app)
        self.assertIn("enqueueDisposableFileImports", app)
        self.assertIn("setDisposableFileImportHandler", main)
        self.assertIn("setDisposableFileImportHandler", app)
        self.assertIn("resultHandler: { failure in", app)
        self.assertIn("completion(.failure", app)
        self.assertIn("completion(.success)", app)
        self.assertIn("tunnelsManager.addMultiple", importer)
        self.assertIn("resultHandler?(nil)", importer)
        self.assertIn("enqueueDisposableFileImports(urls)", picker)
        self.assertNotIn("TunnelImporter.importFromFile", picker)

    def test_scene_disconnect_detaches_only_its_live_import_context(self):
        scene = self.scene_delegate.read_text()
        app = self.app_delegate
        self.assertIn("clearDisposableFileImportHandler(for: mainVC)", scene)
        self.assertIn("guard mainVC === sourceVC else { return }", app)
        self.assertIn("disposableFileImportQueue.clearOwnership(for: sourceVC)", app)
        self.assertIn("guard mainVC === sourceVC else { return }", app)

    def test_replacement_scene_revokes_old_handlers_before_its_manager_is_ready(self):
        scene = self.scene_delegate.read_text()
        app = self.app_delegate
        queue = (IOS / "SceneImportQueue.swift").read_text()
        connect = scene[scene.index("func scene("):scene.index("func scene(_ scene: UIScene, openURLContexts")]
        claim = app[app.index("func claimDisposableFileImportOwnership"):app.index("func setDisposableFileImportHandler")]

        self.assertIn("claimDisposableFileImportOwnership(for: mainVC)", connect)
        self.assertLess(connect.index("claimDisposableFileImportOwnership"), connect.index("window.makeKeyAndVisible"))
        self.assertNotIn("appDelegate?.mainVC = mainVC", connect)
        self.assertIn("mainVC = sourceVC", claim)
        self.assertIn("disposableFileImportQueue.claimOwnership(for: sourceVC)", claim)
        self.assertLess(claim.index("disposableFileImportQueue.claimOwnership"), claim.index("mainVC = sourceVC"))
        self.assertIn("disposableFileImportQueue.clearOwnership(for: sourceVC)", app)
        self.assertGreaterEqual(app.count("}, for: sourceVC)"), 2)
        self.assertIn("guard currentOwner === owner else { return }", queue)
        self.assertIn("importer = nil", queue)
        self.assertIn("errorPresenter = nil", queue)

    def test_delayed_manager_initialization_cannot_attach_a_disconnected_scene(self):
        app = self.app_delegate
        main = self.main_controller
        self.assertIn("guard mainVC === sourceVC else { return }", app)
        self.assertIn("setDisposableFileImportHandler", main)

    def test_import_errors_are_queued_until_the_live_alert_is_dismissed(self):
        app = self.app_delegate
        importer = (ROOT / "Sources/WireGuardApp/UI/TunnelImporter.swift").read_text()
        self.assertIn("setErrorPresenter", app)
        self.assertIn("resultHandler", app)
        self.assertIn("resultHandler", importer)
        self.assertIn("onDismissal", app)
        presenter = (IOS / "ErrorPresenter.swift").read_text()
        self.assertIn("alert?.dismiss(animated: true, completion: onDismissal)", presenter)

    def test_scene_lifecycle_refreshes_status_and_shortcuts(self):
        source = self.scene_delegate.read_text()
        self.assertIn("sceneDidBecomeActive", source)
        self.assertIn("refreshTunnelConnectionStatuses", source)
        self.assertIn("sceneWillResignActive", source)
        self.assertIn("QuickActionItem.createItems", source)

    def test_scene_restores_selection_without_replaying_a_toggle(self):
        scene = self.scene_delegate.read_text()
        self.assertIn("stateRestorationActivity(for scene:", scene)
        self.assertIn("session.stateRestorationActivity", scene)
        self.assertIn("tunnelNameForRestoration", scene)
        self.assertIn("mainVC.tunnelNameForRestoration() != tunnelName", scene)
        self.assertIn("shouldToggleStatus: false", scene)

    def test_shortcut_dispatch_is_shared_by_scene_and_application_fallback(self):
        scene = self.scene_delegate.read_text()
        app = self.app_delegate
        self.assertIn("mainVC?.handleShortcutItem", scene)
        self.assertIn("func handleShortcutItem(_ shortcutItem:", self.main_controller)
        self.assertIn("mainVC?.handleShortcutItem", app)

    def test_pending_imports_and_shortcuts_are_queued_until_manager_ready(self):
        source = self.main_controller
        self.assertIn("pendingTunnelsManagerActions", source)
        self.assertIn("performWhenTunnelsManagerReady", source)
        self.assertIn("pendingTunnelsManagerActions.forEach", source)

    def test_split_keeps_empty_detail_collapse_for_compact_layouts(self):
        source = self.main_controller
        self.assertIn("class MainViewController: UISplitViewController", source)
        self.assertIn("collapseSecondary", source)
        self.assertIn("return isDetailVCEmpty", source)
        self.assertIn("TunnelDetailRestoration.tunnelName", source)
        self.assertIn("viewController.children", source)
        self.assertIn("childViewControllers.map", source)
        self.assertNotIn("UIScreen.main", source)
        self.assertNotIn("userInterfaceIdiom", source)


if __name__ == "__main__":
    unittest.main()
