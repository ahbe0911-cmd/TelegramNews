#!/usr/bin/env python3
"""Check pinned Forkgram Android library output before any Gozar integration.

A successful standalone Forkgram app build does NOT prove that its entire
engine is available as a reusable library. This script inspects the actual
Android AAR, reports missing native code and never labels an APK integrated.
"""
from __future__ import annotations

import argparse
import io
import json
import pathlib
import sys
import zipfile

CORE_CLASS = "org/telegram/ui/LaunchActivity.class"
APP_CLASS = "org/telegram/messenger/ApplicationLoader.class"
NATIVE_LIBRARY = "jni/arm64-v8a/libtmessages.49.so"


def inspect(path: pathlib.Path) -> dict[str, object]:
    with zipfile.ZipFile(path) as aar:
        members = set(aar.namelist())
        required = ["AndroidManifest.xml", "classes.jar", NATIVE_LIBRARY]
        absent = [name for name in required if name not in members]
        classes = set()
        if "classes.jar" in members:
            with zipfile.ZipFile(io.BytesIO(aar.read("classes.jar"))) as jar:
                classes = set(jar.namelist())
        for name in [CORE_CLASS, APP_CLASS]:
            if name not in classes:
                absent.append(f"classes.jar!/{name}")
        native = sorted(x for x in members if x.startswith("jni/") and x.endswith(".so"))
        return {
            "file": str(path),
            "bytes": path.stat().st_size,
            "has_launch_activity": CORE_CLASS in classes,
            "has_application_loader": APP_CLASS in classes,
            "native_libraries": native,
            "missing": absent,
            "usable_as_unmodified_standalone_library": False,
            "integrated_with_gozar": False,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("aar", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    result = inspect(args.aar)
    out = json.dumps(result, ensure_ascii=False, indent=2)
    print(out)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(out + "\n", encoding="utf-8")
    return 1 if result["missing"] else 0


if __name__ == "__main__":
    sys.exit(main())
