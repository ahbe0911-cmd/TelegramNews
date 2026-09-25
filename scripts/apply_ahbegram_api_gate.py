#!/usr/bin/env python3
"""Integrate the native API gate into a *temporary* pinned Forkgram checkout.

No checked-in upstream source is rewritten: CI runs this script inside its own
working tree after apply_ahbegram_branding.py. Fail if upstream anchors change.
"""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "third_party/forkgram/TMessagesProj"
JAVA = CORE / "src/main/java"
MANIFEST = CORE / "src/main/AndroidManifest.xml"
APPLOADER = JAVA / "org/telegram/messenger/ApplicationLoader.java"
ICONCTRL = JAVA / "org/telegram/ui/LauncherIconController.java"
assert MANIFEST.is_file() and APPLOADER.is_file()

def once(source, old, new, context):
    assert source.count(old) == 1, f"Upstream {context} anchor changed: {source.count(old)}"
    return source.replace(old, new, 1)

# Native Android activities/services: no WebView or separate APK.
dest = JAVA / "ir/channel/ahbegram"
dest.mkdir(parents=True, exist_ok=True)
for name in ("AhbegramApiCredentials.java", "AhbegramApiGateActivity.java",
             "AhbegramApiVerifyService.java"):
    shutil.copyfile(ROOT / "native/ahbegram" / name, dest / name)

application = APPLOADER.read_text()
application = once(application,
    "        super.onCreate();\n\n        // AndroidUtilities",
    "        super.onCreate();\n"
    "        ir.channel.ahbegram.AhbegramApiCredentials.applySaved(this);\n\n"
    "        // AndroidUtilities", "ApplicationLoader.onCreate API restore")
application = once(application,
    "        if (applicationInited || applicationContext == null) {\n            return;\n        }",
    "        if (applicationInited || applicationContext == null) {\n            return;\n        }\n"
    "        if (!ir.channel.ahbegram.AhbegramApiCredentials.isConfigured(applicationContext)\n"
    "                && !ir.channel.ahbegram.AhbegramApiCredentials.verifierProcessPermitted) {\n"
    "            return;\n        }", "post-init network gate")
application = once(application,
    "        AndroidUtilities.runOnUIThread(ApplicationLoader::startPushService);\n"
    "        LauncherIconController.tryFixLauncherIconIfNeeded();\n"
    "        ProxyRotationController.init();",
    "        if (ir.channel.ahbegram.AhbegramApiCredentials.isConfigured(this)) {\n"
    "            AndroidUtilities.runOnUIThread(ApplicationLoader::startPushService);\n"
    "            ProxyRotationController.init();\n"
    "        }\n"
    "        LauncherIconController.tryFixLauncherIconIfNeeded();",
    "prevent premature network init without user API credentials")
APPLOADER.write_text(application)

# Old upstream icon presets must never re-enable the paper-plane launcher.
controller = ICONCTRL.read_text()
controller = once(controller,
    "        for (LauncherIcon icon : LauncherIcon.values()) {\n"
    "            if (isEnabled(icon)) {\n                return;\n            }\n        }\n\n"
    "        setIcon(LauncherIcon.DEFAULT);",
    "        if (!isEnabled(LauncherIcon.DEFAULT)) {\n"
    "            setIcon(LauncherIcon.DEFAULT);\n        }",
    "icon restoration")
controller = once(controller,
    "    public static void setIcon(LauncherIcon icon) {\n"
    "        Context ctx = ApplicationLoader.applicationContext;",
    "    public static void setIcon(LauncherIcon icon) {\n"
    "        icon = LauncherIcon.DEFAULT; // ahbegram has one own icon.\n"
    "        Context ctx = ApplicationLoader.applicationContext;",
    "disallow selecting upstream launcher icons")
ICONCTRL.write_text(controller)

# All EXTERNAL entry points (links, shares and launcher) first enter the gate.
# Internal notifications still use the native LaunchActivity, which cannot
# be reached externally until the pair has passed the server preflight.
xml = MANIFEST.read_text()
launch_start = xml.index('        <activity\n            android:name="org.telegram.ui.LaunchActivity"')
launch_end = xml.index('</activity>', launch_start) + len('</activity>')
launch = xml[launch_start:launch_end]
filters = re.findall(r'<intent-filter(?:\s[^>]*)?>[\s\S]*?</intent-filter>', launch)
assert len(filters) >= 7, f"Unexpected upstream LaunchActivity intent filters: {len(filters)}"
assert 'android:exported="true"' in launch
launch_locked = launch.replace('android:exported="true"',
                               'android:exported="false"', 1)
for filter_xml in filters:
    launch_locked = launch_locked.replace(filter_xml, "", 1)
xml = xml[:launch_start] + launch_locked + xml[launch_end:]

# Launcher alias must point to a declared activity earlier in the manifest.
gate = """        <activity
            android:name="ir.channel.ahbegram.AhbegramApiGateActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@android:style/Theme.Material.Light.NoActionBar">
"""
for intent in filters:
    gate += "            " + intent.strip() + "\n"
gate += """        </activity>
        <service
            android:name="ir.channel.ahbegram.AhbegramApiVerifyService"
            android:exported="false"
            android:process=":api_verify" />
"""
alias = ('android:name="org.telegram.messenger.DefaultIcon"\n'
         '            android:targetActivity="org.telegram.ui.LaunchActivity"')
xml = once(xml, alias,
    'android:name="org.telegram.messenger.DefaultIcon"\n'
    '            android:targetActivity="ir.channel.ahbegram.AhbegramApiGateActivity"',
    "default launcher alias")
marker = '        <activity-alias\n            android:enabled="true"\n'
xml = once(xml, marker, gate + "\n" + marker, "declaration before launcher alias")
MANIFEST.write_text(xml)

# Runtime onboarding intentionally overrides any CI BuildConfig placeholders.
# Do not treat APP_ID=0/APP_HASH=0 as valid or enable the phone page on syntax.
print("Staged ahbegram API-first entry + isolated Telegram preflight service.")
print("Old LaunchActivity external filters forwarded by the gate.")
