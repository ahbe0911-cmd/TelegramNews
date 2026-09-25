#!/usr/bin/env python3
"""Apply ahbegram's own visual identity to the pinned Forkgram working tree.

Only executed inside a disposable CI checkout, never committed inside the
upstream submodule. Preserve MTProto source namespaces, protocol links,
upstream licenses and factual Telegram service references.
"""
from pathlib import Path
from PIL import Image
import json
import re

ROOT = Path(__file__).resolve().parents[1]
FORK = ROOT / "third_party/forkgram"
CORE = FORK / "TMessagesProj"
APP = FORK / "TMessagesProj_App"
ICON = ROOT / "branding/ahbegram-symbol.webp"
assert ICON.is_file(), "Exact user-supplied logo asset missing. Stop the build."
assert (CORE / "src/main/AndroidManifest.xml").is_file()
assert (APP / "build.gradle").is_file()


def replace_one(path, old, new):
    source = path.read_text(encoding="utf-8")
    assert source.count(old) == 1, f"Unexpected upstream anchor in {path}: {old!r}"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


# Do not reuse Forkgram's package identity or its beta update channel.
gradle = APP / "build.gradle"
replace_one(gradle,
            'defaultConfig.applicationId = "org.forkclient.messenger"',
            'defaultConfig.applicationId = "ir.channel.ahbegram"')
replace_one(gradle,
            'defaultConfig.applicationId = "org.forkgram.messenger"',
            'defaultConfig.applicationId = "ir.channel.ahbegram"')
replace_one(gradle,
            'def appSuffix = fdroid ? "" : ".beta"',
            'def appSuffix = ""')

# Label for the Android installer and app settings.
app_manifest = APP / "src/main/AndroidManifest.xml"
replace_one(app_manifest, 'android:label="@string/AppName"',
            'android:label="ahbegram"')

# Localized app-name resource definitions in all upstream values folders.
names = {"AppName", "AppNameBeta", "AppNameFdroid"}
updated = []
for path in (CORE / "src/main/res").glob("values*/strings.xml"):
    original = path.read_text(encoding="utf-8")
    value = original
    for name in names:
        value = re.sub(
            rf'(<string\s+name="{name}"\s*>)[^<]*(</string>)',
            lambda match: match.group(1) + "ahbegram" + match.group(2),
            value)
    if value != original:
        path.write_text(value, encoding="utf-8")
        updated.append(str(path.relative_to(FORK)))
assert any(p.endswith("values/strings.xml") for p in updated), "AppName was not replaced"

# Default launcher alias is the real home-screen icon, not only the
# <application> icon. Do not leave the old plane selected on first install.
core_manifest = CORE / "src/main/AndroidManifest.xml"
replace_one(core_manifest,
            'android:name="org.telegram.messenger.DefaultIcon"\n'
            '            android:targetActivity="org.telegram.ui.LaunchActivity"\n'
            '            android:icon="@mipmap/icon_01_launcher"\n'
            '            android:roundIcon="@mipmap/icon_01_launcher_round"',
            'android:name="org.telegram.messenger.DefaultIcon"\n'
            '            android:targetActivity="org.telegram.ui.LaunchActivity"\n'
            '            android:icon="@mipmap/ic_launcher"\n'
            '            android:roundIcon="@mipmap/ic_launcher_round"')

# Preserve the provided symbol; do not approximate it with a stock Telegram
# icon. Only resample/position it to fit standard launcher density buckets.
res = CORE / "src/main/res"
source = Image.open(ICON).convert("RGBA")
densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144,
             "xxxhdpi": 192}
for density, width in densities.items():
    dest = res / ("mipmap-" + density)
    dest.mkdir(exist_ok=True, parents=True)
    symbol = source.resize((width, width), Image.Resampling.LANCZOS)
    symbol.save(dest / "ic_launcher.png", optimize=True)
    symbol.save(dest / "ic_launcher_round.png", optimize=True)
    foreground = Image.new("RGBA", (round(width * 2.25), round(width * 2.25)),
                           (255, 255, 255, 255))
    artwork = source.resize((round(foreground.width * .73),
                             round(foreground.height * .73)), Image.Resampling.LANCZOS)
    foreground.alpha_composite(
        artwork, ((foreground.width - artwork.width) // 2,
                  (foreground.height - artwork.height) // 2))
    foreground.save(dest / "ahbegram_foreground.png", optimize=True)
for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
    target = res / "mipmap-anydpi-v26" / name
    target.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@android:color/white" />\n'
        '    <foreground android:drawable="@mipmap/ahbegram_foreground" />\n'
        '</adaptive-icon>\n', encoding="utf-8")

# An upstream change must not silently revive its own icon or app name.
assert "Fork Client" not in (res / "values/strings.xml").read_text()
assert "org.forkclient.messenger" not in gradle.read_text().split("defaultConfig.applicationId =", 1)[1].split("\n", 1)[0]
report = ROOT / "build-reports/ahbegram-branding.json"
report.parent.mkdir(exist_ok=True)
report.write_text(json.dumps({"app_name": "ahbegram",
    "application_id": "ir.channel.ahbegram",
    "icon_source": str(ICON.relative_to(ROOT)),
    "localized_resources_updated": updated,
    "upstream_protocol_namespaces_preserved": True}, indent=2), encoding="utf-8")
print("Applied ahbegram name and exact uploaded speech-mark launcher artwork.")
