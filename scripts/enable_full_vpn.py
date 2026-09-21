#!/usr/bin/env python3
"""Add the Android VPN and pinned Xray AAR to the generated Flutter host.

Call after prepare_android.py and configure_variant.py. This does not make the
VPN work without an actual core: the Android build fetches a checksum-pinned
AAR and SystemVpnService passes Android's real TUN fd to its core controller.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
host = ROOT / 'android'
assert host.is_dir(), 'Run prepare_android.py before enabling VPN'
activities = list((host / 'app/src/main/kotlin').rglob('MainActivity.kt'))
assert len(activities) == 1, activities
activity = activities[0]
code = activity.read_text()
assert code.count('super.configureFlutterEngine(flutterEngine)') == 1
assert code.count('class MainActivity : FlutterActivity() {') == 1
code = code.replace(
    'super.configureFlutterEngine(flutterEngine)',
    'super.configureFlutterEngine(flutterEngine)\n'
    '        SystemVpnBridge.attach(this, flutterEngine)', 1,
)
code = code.replace('import io.flutter.embedding.android.FlutterActivity',
    'import android.content.Intent\n'
    'import io.flutter.embedding.android.FlutterActivity', 1)
code = code.replace('class MainActivity : FlutterActivity() {', '''
class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        SystemVpnBridge.onActivityResult(this, requestCode, resultCode)
    }
''', 1)
activity.write_text(code)
for name in ('SystemVpnBridge.kt', 'SystemVpnService.kt', 'VpnRoutingPolicy.kt', 'InternalTelegramProxyService.kt'):
    (activity.parent / name).write_bytes((ROOT / 'native' / name).read_bytes())

manifest = host / 'app/src/main/AndroidManifest.xml'
source = manifest.read_text()
assert source.count('<application') == 1
assert source.count('</application>') == 1
source = source.replace('<application', '''<queries>
        <intent>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent>
    </queries>
    <application''', 1)
source = source.replace('<application', '''
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <application''', 1)
source = source.replace('</application>', '''
        <service
            android:name=".InternalTelegramProxyService"
            android:enabled="true"
            android:exported="false"
            android:process=":telegram_proxy"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User enabled persistent Telegram SOCKS proxy using selected Xray server" />
        </service>
        <service
            android:name=".SystemVpnService"
            android:exported="false"
            android:enabled="true"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:foregroundServiceType="specialUse">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Full device VPN tunnel for user-selected Xray proxy" />
        </service>
    </application>''', 1)
manifest.write_text(source)

gradle = host / 'app/build.gradle.kts'
source = gradle.read_text()
assert source.count('android {') == 1
source = source.replace('android {', '''android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
''', 1)
source += '\ndependencies { implementation(files("libs/libv2ray.aar")) }\n'
gradle.write_text(source)
print('Configured real Android VPN service, platform consent, TUN FD and Xray AAR dependency')
