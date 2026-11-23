"""Native Clang import checks for the WireGuardKitC umbrella module."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = ROOT / "Sources/WireGuardKitC"


@unittest.skipUnless(shutil.which("xcrun"), "requires an Apple Xcode toolchain")
class WireGuardKitCHeaderTests(unittest.TestCase):
    def test_umbrella_header_imports_with_the_iphone_simulator_sdk(self):
        cache_root = Path(
            os.environ.get(
                "WIREGUARD_HEADER_TEST_CACHE",
                Path.home() / ".hermes/cache/scratch/wireguardkitc-header-tests",
            )
        )
        cache_root.mkdir(parents=True, exist_ok=True)
        source = cache_root / "import-wireguardkitc.m"
        source.write_text("@import WireGuardKitC;\n")
        module_cache = cache_root / "clang-module-cache"
        module_cache.mkdir(parents=True, exist_ok=True)

        result = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "iphonesimulator",
                "clang",
                "-fmodules",
                f"-fmodules-cache-path={module_cache}",
                f"-fmodule-map-file={MODULE_DIR / 'module.modulemap'}",
                "-I",
                str(MODULE_DIR),
                "-fsyntax-only",
                str(source),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"WireGuardKitC failed to import:\n{result.stdout}\n{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
