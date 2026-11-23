"""Build configuration checks for the iOS simulator Go bridge target."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAKEFILE = ROOT / "Sources/WireGuardKitGo/Makefile"


class GoSimulatorPlatformTests(unittest.TestCase):
    def test_simulator_bridge_uses_ios_runtime_for_arm64_and_amd64(self):
        makefile = MAKEFILE.read_text()
        self.assertRegex(makefile, r"(?m)^GOOS_iphonesimulator\s*:=\s*ios$")


if __name__ == "__main__":
    unittest.main()
