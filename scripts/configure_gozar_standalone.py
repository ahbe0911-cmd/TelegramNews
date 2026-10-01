#!/usr/bin/env python3
"""Build Gozar as launcher + notes only, with no VPN components."""

from pathlib import Path

root = Path(__file__).resolve().parents[1]

(root / 'pubspec.yaml').write_text('''name: telegram_news
description: Gozar launcher and local notes
publish_to: none
version: 1.6.0+1
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
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
):
    (activity.parent / name).write_bytes((root / 'native' / name).read_bytes())

# Purge every generated VPN/tunnel implementation from the Gozar Android host.
for name in (
    'GozarVpnBridge.kt',
    'GozarVpnService.kt',
    'GozarDirectAppPolicy.kt',
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

(root / 'android/app/libs/libv2ray.aar').unlink(missing_ok=True)

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
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
)
source = source.replace('<application', permissions + '    <application', 1)

source = source.replace(
    '</application>',
    '''
        <activity
            android:name=".GozarWebActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar" />
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

final_manifest = manifest.read_text()
for forbidden in (
    'android.permission.BIND_VPN_SERVICE',
    'android.net.VpnService',
    'GozarVpnService',
    'SystemVpnService',
    'FOREGROUND_SERVICE_SPECIAL_USE',
):
    assert forbidden not in final_manifest, forbidden

assert 'android.permission.QUERY_ALL_PACKAGES' in final_manifest
assert 'android.permission.POST_NOTIFICATIONS' in final_manifest

main_code = activity.read_text()
assert 'GozarPlatformBridge.attach(this, flutterEngine)' in main_code
assert 'GozarVpnBridge' not in main_code
assert 'SystemVpnBridge' not in main_code

print('Gozar: launcher + notes + reminders only; VPN fully removed')
