#!/usr/bin/env python3
"""Reject a falsely labeled Gozar + Forkgram APK before any manual distribution.

A passing structural check alone does NOT prove that sign-in, messages, media,
notifications, back navigation, VPN routing or notes work on a physical phone.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile

EXPECTED_PACKAGE = "ir.channel.gozar_vpn"
EXPECTED_LAUNCHER = "ir.channel.telegram_news.MainActivity"


def check(apk: Path, aapt: str) -> None:
    assert apk.is_file() and apk.stat().st_size > 20_000_000, (
        f"Not a plausible combined APK: {apk}"
    )
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        native = sorted(name for name in names if name.endswith(".so"))
        assert "classes.dex" in names, "No Android bytecode"
        assert "AndroidManifest.xml" in names, "No Android manifest"
        assert any(name.endswith("/libflutter.so") for name in native), (
            "Flutter runtime missing"
        )
        assert any(re.search(r"/libtmessages\\.[0-9]+\\.so$", name)
                   for name in native), "Forkgram native messaging library missing"
        assert any(name.startswith("assets/flutter_assets/") for name in names), (
            "Gozar Flutter assets missing"
        )
        assert any(name.startswith("lib/arm64-v8a/") for name in native), (
            "ARM64 Android target missing"
        )
    result = subprocess.run([aapt, "dump", "badging", str(apk)],
                            capture_output=True, text=True, check=True)
    pkg = re.search(r"(?m)^package: name='([^']+)'", result.stdout)
    assert pkg and pkg.group(1) == EXPECTED_PACKAGE, (
        f"Incorrect package identity: {pkg.group(1) if pkg else 'unknown'}"
    )
    launcher = re.search(r"(?m)^launchable-activity: name='([^']+)'", result.stdout)
    assert launcher and launcher.group(1) == EXPECTED_LAUNCHER, (
        f"Unexpected launcher: {launcher.group(1) if launcher else 'none'}"
    )
    print(f"STRUCTURAL CHECK PASS: {apk.name}; single package {EXPECTED_PACKAGE}; "
          "Flutter assets, Forkgram native engine and ARM64 libraries present.")
    print("DEVICE TESTS AND RELEASE SIGNING STILL REQUIRED; NOT USER-READY.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--aapt", default="aapt")
    args = parser.parse_args()
    try:
        check(args.apk, args.aapt)
    except (AssertionError, FileNotFoundError, subprocess.CalledProcessError,
            zipfile.BadZipFile) as error:
        print(f"STRUCTURAL CHECK FAILED: {error}", file=sys.stderr)
        sys.exit(1)
