#!/usr/bin/env python3
"""Build Gozar as a launcher + notes app with no VPN components."""

from pathlib import Path

root = Path(__file__).resolve().parents[1]

(root / 'pubspec.yaml').write_text('''name: telegram_news
description: Gozar launcher and local notes
publish_to: none
version: 1.3.0+1
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

# Only non-network Gozar platform helpers are packaged.
for name in ('GozarPlatformBridge.kt', 'GozarWebActivity.kt',
             'GozarReminderBridge.kt'):
    (activity.parent / name).write_bytes((root / 'native' / name).read_bytes())

# Explicitly remove old generated network/tunnel components if a reused host
# ever contains them. They are not part of this application variant.
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

# Let the launcher enumerate only activities that explicitly advertise the
# standard Android launcher intent.
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

# Local reminder permissions only.
permissions = (
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
    'BIND_VPN_SERVICE',
    'android.net.VpnService',
    'SystemVpnService',
    'InternalTelegramProxyService',
    'FOREGROUND_SERVICE_SPECIAL_USE',
):
    assert forbidden not in final_manifest, forbidden

assert 'GozarPlatformBridge.attach' in activity.read_text()
assert 'SystemVpnBridge' not in activity.read_text()
print('Gozar: launcher + notes only; no VPN service or tunnel engine packaged')
