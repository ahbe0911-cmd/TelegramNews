#!/usr/bin/env python3
"""Build Gozar as launcher + notes with an Xray VPN controlled only in Settings."""

from pathlib import Path

root = Path(__file__).resolve().parents[1]

(root / 'pubspec.yaml').write_text('''name: telegram_news
description: Gozar launcher, notes and Settings-only Xray VPN
publish_to: none
version: 1.5.0+1
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_secure_storage: ^9.2.4
  shared_preferences: 2.3.2
  shamsi_date: ^1.0.4
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 4.0.0
flutter:
  uses-material-design: true
  fonts:
    - family: Vazirmatn
      fonts:
        - asset: assets/fonts/Vazirmatn-Regular.ttf
          weight: 400
        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
''')

host = root / 'android/app/src/main'
activity = next((host / 'kotlin').rglob('MainActivity.kt'))
activity.write_text('''package ir.channel.telegram_news

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GozarPlatformBridge.attach(this, flutterEngine)
        GozarReminderBridge.attach(this, flutterEngine)
        GozarVpnBridge.attach(this, flutterEngine)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        GozarVpnBridge.onActivityResult(this, requestCode, resultCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        GozarReminderBridge.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        GozarReminderBridge.onNewIntent(intent)
    }
}
''')

for name in (
    'GozarPlatformBridge.kt',
    'GozarWebActivity.kt',
    'GozarReminderBridge.kt',
    'GozarVpnBridge.kt',
    'GozarVpnService.kt',
    'GozarDirectAppPolicy.kt',
):
    (activity.parent / name).write_bytes((root / 'native' / name).read_bytes())

# Remove all legacy VPN implementations. The standalone build packages only
# the dedicated Xray-only GozarVpnBridge/GozarVpnService pair.
for name in (
    'SystemVpnBridge.kt',
    'SystemVpnService.kt',
    'WireGuardController.kt',
    'VpnRoutingPolicy.kt',
    'AutomaticBypassPolicy.kt',
    'InternalTelegramProxyService.kt',
    'GozarSocialWebView.kt',
    'GozarSocialDownloads.kt',
    'GozarTelegramWebView.kt',
):
    (activity.parent / name).unlink(missing_ok=True)

manifest = host / 'AndroidManifest.xml'
source = manifest.read_text()

if '<queries>' not in source:
    source = source.replace(
        '<application',
        '''<queries>
        <intent>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent>
    </queries>
    <application''',
        1,
    )

permissions = (
    '    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>\n'
)
source = source.replace('<application', permissions + '    <application', 1)

source = source.replace(
    '</application>',
    '''
        <activity
            android:name=".GozarWebActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar" />
        <service
            android:name=".GozarVpnService"
            android:enabled="true"
            android:exported="false"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:foregroundServiceType="specialUse">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User-started Xray VPN tunnel controlled only from Gozar Settings" />
        </service>
        <receiver
            android:name=".GozarReminderReceiver"
            android:exported="false" />
        <receiver
            android:name=".GozarReminderBootReceiver"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
                <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
            </intent-filter>
        </receiver>
    </application>''',
    1,
)
manifest.write_text(source)

gradle = root / 'android/app/build.gradle.kts'
gradle_source = gradle.read_text()
assert gradle_source.count('android {') == 1
gradle_source = gradle_source.replace(
    'android {',
    '''android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
''',
    1,
)
gradle_source += '\ndependencies { implementation(files("libs/libv2ray.aar")) }\n'
gradle.write_text(gradle_source)

final_manifest = manifest.read_text()
assert 'android.permission.BIND_VPN_SERVICE' in final_manifest
assert 'android.net.VpnService' in final_manifest
assert 'GozarVpnService' in final_manifest
assert 'android.permission.QUERY_ALL_PACKAGES' in final_manifest
assert 'SystemVpnService' not in final_manifest
assert 'WireGuard' not in final_manifest
assert 'InternalTelegramProxyService' not in final_manifest

main_code = activity.read_text()
assert 'GozarVpnBridge.attach(this, flutterEngine)' in main_code
assert 'SystemVpnBridge' not in main_code
assert 'WireGuard' not in main_code

print('Gozar: full launcher visibility + notes + smart-bypass Settings Xray VPN')
