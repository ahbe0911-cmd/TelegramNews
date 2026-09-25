#!/usr/bin/env python3
"""Apply isolated ahbegram branding + runtime API gate to a PINNED Forkgram checkout.

Upstream is a git submodule, patched only in the ephemeral Actions workspace.
Fail loudly if the pinned source layout changes; never mutate the stable Gozar
branch or silently patch an unexpected upstream version.
"""
from pathlib import Path
from PIL import Image
import re
import shutil
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
fork = root / "third_party" / "forkgram"
core = fork / "TMessagesProj"
app = fork / "TMessagesProj_App"
brand = root / "assets" / "ahbegram" / "brand-icon.png"
assert brand.is_file(), "Original approved ahbegram brand mark not in repository"
assert (core / "src/main/java/org/telegram/ui/LaunchActivity.java").exists()
assert (app / "build.gradle").exists()

def edit_exact(path: Path, old: str, new: str, context: str) -> None:
    content = path.read_text(encoding="utf-8")
    assert content.count(old) == 1, (
        f"Pinned upstream {context} changed unexpectedly ({content.count(old)} matches)"
    )
    path.write_text(content.replace(old, new, 1), encoding="utf-8")

core_java = core / "src/main/java/org/telegram/messenger"
app_java = app / "src/main/java/org/ahbegram"
app_java.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / "native/ahbegram/AhbeApiCredentials.java",
                core_java / "AhbeApiCredentials.java")
shutil.copyfile(root / "native/ahbegram/AhbeApiSetupActivity.java",
                app_java / "AhbeApiSetupActivity.java")

# BuildVars must load accepted credentials before any Telegram network
# connection is initialized after app restart. The first launch has id=0;
# the API gate explicitly fills BuildVars before its preflight request.
vars_path = core_java / "BuildVars.java"
edit_exact(vars_path,
           "        APP_ID = BuildConfig.APP_ID;\n        APP_HASH = BuildConfig.APP_HASH;",
           "        APP_ID = AhbeApiCredentials.readId(ApplicationLoader.applicationContext);\n"
           "        APP_HASH = AhbeApiCredentials.readHash(ApplicationLoader.applicationContext);",
           "dynamic BuildVars API credentials")

launch_path = core / "src/main/java/org/telegram/ui/LaunchActivity.java"
edit_exact(launch_path,
           "    protected void onCreate(Bundle savedInstanceState) {\n        isActive = true;",
           "    protected void onCreate(Bundle savedInstanceState) {\n"
           "        if (!org.telegram.messenger.AhbeApiCredentials.hasVerified(this)) {\n"
           "            android.content.Intent setup = new android.content.Intent();\n"
           '            setup.setClassName(getPackageName(), "org.ahbegram.AhbeApiSetupActivity");\n'
           "            startActivity(setup);\n"
           "            finish();\n"
           "            return;\n"
           "        }\n"
           "        isActive = true;",
           "unauthenticated launcher bypass guard")
loader_path = core_java / "ApplicationLoader.java"
edit_exact(loader_path,
           "        AndroidUtilities.runOnUIThread(ApplicationLoader::startPushService);",
           "        if (AhbeApiCredentials.hasVerified(applicationContext)) {\n"
           "            AndroidUtilities.runOnUIThread(ApplicationLoader::startPushService);\n"
           "        }",
           "pre-configuration push service")

# Keep the ORIGINAL internal Java packages, app-signing and license notices.
# A new Android applicationId ensures this independent client does not replace
# the installed upstream Forkgram or Gozar.
build_gradle = app / "build.gradle"
edit_exact(build_gradle,
           'defaultConfig.applicationId = "org.forkclient.messenger"',
           'defaultConfig.applicationId = "org.ahbegram.client"',
           "standalone package identity")
edit_exact(build_gradle,
           'def appSuffix = fdroid ? "" : ".beta"',
           'def appSuffix = ""',
           "standalone app suffix")
# F_DROID remains 0 in our CI job (it would override our app ID).

manifest = core / "src/main/AndroidManifest.xml"
src = manifest.read_text(encoding="utf-8")
anchor = '        <activity-alias\n            android:enabled="true"\n            android:name="org.telegram.messenger.DefaultIcon"'
assert src.count(anchor) == 1, "Missing default launcher alias"
setup_declaration = '''        <activity
            android:name="org.ahbegram.AhbeApiSetupActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.Light.NoActionBar"
            android:windowSoftInputMode="adjustResize" />

'''
src = src.replace(anchor, setup_declaration + anchor, 1)
default_start = src.index('<activity-alias', src.index('org.ahbegram.AhbeApiSetupActivity'))
default_end = src.index('</activity-alias>', default_start) + len('</activity-alias>')
alias = src[default_start:default_end]
assert 'android:targetActivity="org.telegram.ui.LaunchActivity"' in alias
alias = alias.replace('android:targetActivity="org.telegram.ui.LaunchActivity"',
                      'android:targetActivity="org.ahbegram.AhbeApiSetupActivity"', 1)
assert 'android:icon="@mipmap/icon_01_launcher"' in alias
alias = alias.replace('@mipmap/icon_01_launcher_round', '@mipmap/ic_launcher_round')
alias = alias.replace('@mipmap/icon_01_launcher', '@mipmap/ic_launcher')
src = src[:default_start] + alias + src[default_end:]
# Icon aliases other than the default are already disabled by upstream; keep
# their internal launcher class names but never expose the old Telegram art.
src, count = re.subn(r'(android:(?:roundIcon|icon)=")@mipmap/(?:ic_original|icon_[0-9]+)_launcher(?:_round|_adaptive)?(")',
                     lambda m: m.group(1) + ('@mipmap/ic_launcher_round' if 'roundIcon' in m.group(1) else '@mipmap/ic_launcher') + m.group(2),
                     src)
assert count >= 5, "Missing upstream optional launcher icon aliases"
manifest.write_text(src, encoding="utf-8")

# All localised *app identity* labels: retain factual references to Telegram
# services in protocol, privacy, attribution and feature explanations.
strings_count = 0
for path in (core / "src/main/res").glob("values*/strings.xml"):
    original = path.read_text(encoding="utf-8")
    updated, n = re.subn(
        r'(<string\s+name="(?:AppName|AppNameBeta|AppNameFdroid)"[^>]*>)([^<]*)(</string>)',
        lambda m: m.group(1) + "ahbegram" + m.group(3),
        original)
    if n:
        path.write_text(updated, encoding="utf-8")
        strings_count += n
assert strings_count >= 3, "Unable to replace app display names"

# Convert user's supplied emblem (not a made-up replacement) to conventional
# and adaptive Android launcher variants without shipping a full-size poster.
source = Image.open(brand).convert("RGBA")
res = core / "src/main/res"
densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
             "xxhdpi": 144, "xxxhdpi": 192}
for density, size in densities.items():
    target = res / ("mipmap-" + density)
    target.mkdir(parents=True, exist_ok=True)
    icon = source.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(target / "ic_launcher.png", optimize=True)
    icon.save(target / "ic_launcher_round.png", optimize=True)
    # Adaptive icon foreground: a safe padded glyph; masks vary by launcher.
    fg_size = round(size * 108 / 48)
    fg = Image.new("RGBA", (fg_size, fg_size), (255, 255, 255, 0))
    glyph = source.resize((round(fg_size * .66), round(fg_size * .66)),
                          Image.Resampling.LANCZOS)
    fg.alpha_composite(glyph, ((fg_size-glyph.width)//2, (fg_size-glyph.height)//2))
    fg.save(target / "ahbe_foreground.png", optimize=True)
adaptive = res / "mipmap-anydpi-v26"
adaptive.mkdir(parents=True, exist_ok=True)
icon_xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ahbe_icon_bg" />
    <foreground android:drawable="@mipmap/ahbe_foreground" />
</adaptive-icon>
'''
(adaptive / "ic_launcher.xml").write_text(icon_xml, encoding="utf-8")
(adaptive / "ic_launcher_round.xml").write_text(icon_xml, encoding="utf-8")
(res / "values" / "ahbe_brand_colors.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?><resources>'
    '<color name="ahbe_icon_bg">#FFFFFF</color></resources>\n',
    encoding="utf-8")

# App icon choice previews must not display any original Telegram airplanes,
# even when the user opens the icon selection screen.
controller = core / "src/main/java/org/telegram/ui/LauncherIconController.java"
icon_source = controller.read_text(encoding="utf-8")
icon_source, replaced = re.subn(r'R\.(?:drawable|mipmap)\.[A-Za-z0-9_]+_(?:background|foreground)_sa',
                                lambda m: ('R.drawable.ahbe_icon_background'
                                           if '.drawable.' in m.group(0)
                                           else 'R.mipmap.ahbe_foreground'),
                                icon_source)
assert replaced >= 8
controller.write_text(icon_source, encoding="utf-8")
(res / "drawable" / "ahbe_icon_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<shape xmlns:android="http://schemas.android.com/apk/res/android">'
    '<solid android:color="#FFFFFF"/></shape>\n',
    encoding="utf-8")

# Ensure our manifest modifications stay parseable before Gradle is invoked.
ET.parse(manifest)
ET.parse(adaptive / "ic_launcher.xml")
print("ahbegram native app staged: first-run API validation, brand mark, "
      "launcher aliases, package identity and dynamic credentials.")
print("App API credentials are entered at runtime; NO credentials are embedded.")
print("This is source staging, NOT a completed device or login test.")
