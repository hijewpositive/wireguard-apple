"""Discoverable runtime tests for the production scene behavior helpers."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

from GoSimulatorPlatformTests import GoSimulatorPlatformTests
from SceneLifecycleContractTests import SceneLifecycleContractTests
from WireGuardKitCHeaderTests import WireGuardKitCHeaderTests

ROOT = Path(__file__).resolve().parents[1]


class SceneBehaviorRuntimeTests(unittest.TestCase):
    def test_production_scene_helpers_execute_regression_scenarios(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("Swift compiler is available on the assigned Mac host")

        temporary_root = os.environ.get("WIREGUARD_TEST_TMPDIR")
        with tempfile.TemporaryDirectory(
            prefix="wireguard-scene-runtime-", dir=temporary_root
        ) as temporary_directory:
            executable = Path(temporary_directory) / "scene-behavior-tests"
            sources = [
                ROOT / "Sources/WireGuardApp/UI/iOS/SceneImportQueue.swift",
                ROOT / "Sources/WireGuardApp/UI/iOS/TunnelDetailRestoration.swift",
                ROOT / "Tests/SceneBehaviorTests.swift",
            ]
            build = subprocess.run(
                [swiftc, *(str(source) for source in sources), "-o", str(executable)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(build.returncode, 0, msg=build.stderr)

            run = subprocess.run(
                [str(executable), temporary_directory],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(run.returncode, 0, msg=run.stderr)
            self.assertIn("PASS: import failures wait for a live presenter and dismissal", run.stdout)
            self.assertIn("PASS: successful imports clean up and proceed in FIFO order", run.stdout)
            self.assertIn("PASS: scene action state resets on reconnection", run.stdout)
            self.assertIn("PASS: nested compact and wide details restore selection", run.stdout)
            self.assertIn("PASS: empty navigation restores no tunnel", run.stdout)


if __name__ == "__main__":
    unittest.main()
