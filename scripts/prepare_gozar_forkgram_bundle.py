#!/usr/bin/env python3
"""Stage a single-APK Gozar + genuine native Forkgram Android build.

Run ONLY inside an ephemeral CI checkout after:
  1. recursively initializing pinned third_party/forkgram,
  2. compiling Gozar Flutter add-to-app AAR,
  3. checking out the pinned Xray AAR and fonts.

This deliberately edits only the CI working copy of the upstream submodule.
The checked-in upstream gitlink stays exact and updateable independently.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import os
import re
import shutil

root = Path(__file__).resolve().parents[1]
fork = root / 'third_party' / 'forkgram'
module = root / 'build' / 'gozar_module'
app = fork / 'TMessagesProj_App'
core = fork / 'TMessagesProj'
repo = module / 'build' / 'host' / 'outputs' / 'repo'
poms = list(repo.rglob('flutter_release-*.pom'))
assert len(poms) == 1, f'Expected one built Flutter release AAR, got {poms}'
pom = ET.parse(poms[0]).getroot()
def value(tag):
    node = next((e for e in pom if e.tag.rsplit('}', 1)[-1] == tag), None)
    assert node is not None and node.text, tag
    return node.text.strip()
coordinate = ':'.join((value('groupId'), value('artifactId'), value('version')))
assert value('artifactId') == 'flutter_release', coordinate
assert poms[0].with_suffix('.aar').is_file(), 'Missing built Flutter AAR'

def replace_once(source, old, new, name):
    assert source.count(old) == 1, f'Unexpected upstream {name}: {source.count(old)}'
    return source.replace(old, new, 1)

# All Telegram screens, including deep-links, media, login and notification
# launches, use Forkgram's real LaunchActivity. Add our bottom bar AROUND
# its existing frame. Fail fast when upstream changes this integration point.
launch_file = core / 'src/main/java/org/telegram/ui/LaunchActivity.java'
launch = launch_file.read_text()
launch = replace_once(launch, 'setContentView(frameLayout);',
    'setContentView(ir.channel.telegram_news.GozarForkgramTabShell.wrap(this, frameLayout));',
    'LaunchActivity content anchor')
launch_file.write_text(launch)
shell_dir = core / 'src/main/java/ir/channel/telegram_news'
shell_dir.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'native/forkgram/GozarForkgramTabShell.java',
                shell_dir / 'GozarForkgramTabShell.java')

# Forkgram's configurable launcher aliases would otherwise create a second
# independent Telegram icon on the home screen.
core_manifest = core / 'src/main/AndroidManifest.xml'
xml = core_manifest.read_text()
aliases = re.findall(r'<activity-alias\b[\s\S]*?</activity-alias>', xml)
assert len(aliases) >= 1, 'Unexpected Forkgram launcher-alias manifest'
disabled = 0
for alias in aliases:
    if 'android.intent.category.LAUNCHER' not in alias:
        continue
    if 'android:enabled=' in alias.split('>', 1)[0]:
        updated = re.sub(r'android:enabled="[^"]+"', 'android:enabled="false"',
                         alias, count=1)
    else:
        updated = alias.replace('<activity-alias', '<activity-alias android:enabled="false"', 1)
    xml = xml.replace(alias, updated, 1)
    disabled += 1
assert disabled >= 1
core_manifest.write_text(xml)

# The Android native app is the HOST. Flutter is packed as a real, separate
# AAR module in this SAME APK (Flutter's official add-to-app mechanism).
settings = fork / 'settings.gradle'
script = settings.read_text()
script = replace_once(script, '        mavenCentral()',
    '        mavenCentral()\n        maven { url = uri("' +
    repo.resolve().as_uri() + '") }\n'
    '        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }',
    'Gradle repositories')
settings.write_text(script)
appgradle = app / 'build.gradle'
script = appgradle.read_text()
script = replace_once(script, "apply plugin: 'com.android.application'",
    "apply plugin: 'com.android.application'\napply plugin: 'kotlin-android'",
    'Kotlin source plugin')
script = replace_once(script, "    implementation project(':TMessagesProj')",
    "    implementation project(':TMessagesProj')\n"
    f"    implementation '{coordinate}'\n"
    "    implementation files('libs/libv2ray.aar')",
    'Forkgram host dependencies')
script = replace_once(script, 'minSdkVersion 21', 'minSdkVersion 24',
    'min Android SDK')
# The packaged app is the SAME package as existing Gozar, not a second app.
script = replace_once(script,
    'defaultConfig.applicationId = "org.forkclient.messenger"',
    'defaultConfig.applicationId = "ir.channel.gozar_vpn"',
    'applicationId')
# Native standalone build uses release signing in the feature experiment;
# for user installation, the EXISTING Gozar release signing key is required.
# Do not use .beta package suffix or a second APK name.
script = replace_once(script, 'def appSuffix = fdroid ? "" : ".beta"',
    'def appSuffix = ""', 'beta suffix')
# F_DROID is explicitly set to 0 at CI so that APK identity is controlled.
appgradle.write_text(script)
libv2ray = app / 'libs' / 'libv2ray.aar'
libv2ray.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'build' / 'libv2ray.aar', libv2ray)

ktdir = app / 'src/main/kotlin/ir/channel/telegram_news'
ktdir.mkdir(parents=True, exist_ok=True)
for name in ('SystemVpnService.kt', 'VpnRoutingPolicy.kt',
             'AutomaticBypassPolicy.kt', 'GozarReminderBridge.kt',
             'GozarWebActivity.kt'):
    shutil.copyfile(root / 'native' / name, ktdir / name)
shutil.copyfile(root / 'native/forkgram/GozarForkgramBridge.kt',
                ktdir / 'GozarForkgramBridge.kt')
bridge = (root / 'native/SystemVpnBridge.kt').read_text()
a = bridge.index('                    "startInternal" -> {')
b = bridge.index('                    "openShortcutApp" -> {', a)
bridge = bridge[:a] + bridge[b:]
assert 'InternalTelegramProxyService' not in bridge
(ktdir / 'SystemVpnBridge.kt').write_text(bridge)
(ktdir / 'MainActivity.kt').write_text("""package ir.channel.telegram_news

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        SystemVpnBridge.attach(this, engine)
        GozarReminderBridge.attach(this, engine)
        GozarForkgramBridge.attach(this, engine)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(code: Int, result: Int, data: Intent?) {
        super.onActivityResult(code, result, data)
        SystemVpnBridge.onActivityResult(this, code, result)
    }

    override fun onRequestPermissionsResult(
        code: Int, permissions: Array<out String>, results: IntArray
    ) {
        super.onRequestPermissionsResult(code, permissions, results)
        GozarReminderBridge.onRequestPermissionsResult(code, results)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        GozarReminderBridge.onNewIntent(intent)
        GozarForkgramBridge.onNewIntent(intent)
    }
}
""")

# Forkgram keeps its own ApplicationLoaderImpl, services and native resources.
# The Gozar screen and VPN live beside them in this one Android process/package.
manifest_file = app / 'src/main/AndroidManifest.xml'
manifest = manifest_file.read_text()
manifest = replace_once(manifest, 'tools:replace="name"',
    'tools:replace="name,android:label,android:icon"', 'manifest application merge')
manifest = replace_once(manifest, '<application',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
    '    <application', 'manifest permission anchor')
manifest = replace_once(manifest, 'android:label="@string/AppName"',
    'android:label="گذر"', 'Gozar label')
native_declarations = """
        <activity android:name="ir.channel.telegram_news.MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:theme="@android:style/Theme.Material.Light.NoActionBar">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@android:style/Theme.Material.Light.NoActionBar" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name="ir.channel.telegram_news.GozarWebActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar"/>
        <service android:name="ir.channel.telegram_news.SystemVpnService"
            android:exported="false"
            android:enabled="true"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:foregroundServiceType="specialUse">
            <intent-filter>
                <action android:name="android.net.VpnService"/>
            </intent-filter>
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User-initiated Gozar VPN using an Xray TUN tunnel"/>
        </service>
        <receiver android:name="ir.channel.telegram_news.GozarReminderReceiver"
            android:exported="false"/>
        <receiver android:name="ir.channel.telegram_news.GozarReminderBootReceiver"
            android:enabled="true" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.TIME_SET"/>
                <action android:name="android.intent.action.TIMEZONE_CHANGED"/>
                <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"/>
            </intent-filter>
        </receiver>
"""
manifest = replace_once(manifest, '</application>',
    native_declarations + '\n    </application>', 'host application contents')
manifest_file.write_text(manifest)

# Apply credentials only through CI secrets; build-only checks can use upstream
# placeholders but MUST NOT publish a login-capable user APK.
app_id = os.environ.get('FORKGRAM_APP_ID', '').strip()
app_hash = os.environ.get('FORKGRAM_APP_HASH', '').strip()
if app_id or app_hash:
    assert app_id.isdigit() and int(app_id) > 0
    assert re.fullmatch(r'[0-9a-fA-F]{32}', app_hash), 'Invalid API hash format'
    props = fork / 'gradle.properties'
    old = props.read_text()
    old = re.sub(r'^APP_ID\\s*=.*
    old = re.sub(r'^APP_HASH\\s*=.*
    props.write_text(old)
elif os.environ.get('BUILD_ONLY') != '1':
    raise SystemExit('Own Telegram APP_ID and APP_HASH are required for usable login')

print('Staged one APK host containing real Forkgram + Gozar Flutter AAR.')
print('Flutter Maven coordinate:', coordinate)
print('Credentials:', 'provided securely' if app_id else 'missing (BUILD ONLY)')
, 'APP_ID=' + app_id, old, count=1, flags=re.M)
    old = re.sub(r'^APP_HASH=.*$', 'APP_HASH=' + app_hash, old, count=1, flags=re.M)
    props.write_text(old)
elif os.environ.get('BUILD_ONLY') != '1':
    raise SystemExit('Own Telegram APP_ID and APP_HASH are required for usable login')

print('Staged one APK host containing real Forkgram + Gozar Flutter AAR.')
print('Flutter Maven coordinate:', coordinate)
print('Credentials:', 'provided securely' if app_id else 'missing (BUILD ONLY)')
, 'APP_HASH=' + app_hash, old, count=1, flags=re.M)
    props.write_text(old)
elif os.environ.get('BUILD_ONLY') != '1':
    raise SystemExit('Own Telegram APP_ID and APP_HASH are required for usable login')

print('Staged one APK host containing real Forkgram + Gozar Flutter AAR.')
print('Flutter Maven coordinate:', coordinate)
print('Credentials:', 'provided securely' if app_id else 'missing (BUILD ONLY)')
, 'APP_ID=' + app_id, old, count=1, flags=re.M)
    old = re.sub(r'^APP_HASH=.*$', 'APP_HASH=' + app_hash, old, count=1, flags=re.M)
    props.write_text(old)
elif os.environ.get('BUILD_ONLY') != '1':
    raise SystemExit('Own Telegram APP_ID and APP_HASH are required for usable login')

print('Staged one APK host containing real Forkgram + Gozar Flutter AAR.')
print('Flutter Maven coordinate:', coordinate)
print('Credentials:', 'provided securely' if app_id else 'missing (BUILD ONLY)')
