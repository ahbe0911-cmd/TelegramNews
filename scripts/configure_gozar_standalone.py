#!/usr/bin/env python3
"""Give Gozar its OWN small dependency graph and VPN-only Android host.

Invoked only in the gozar matrix build, after prepare_android.py,
configure_variant.py, and enable_full_vpn.py. The two Telegram applications
are built without invoking enable_full_vpn.py at all.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
(root / 'pubspec.yaml').write_text('''name: telegram_news
description: Gozar standalone Android VPN
publish_to: none
version: 1.2.0+1
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
        SystemVpnBridge.attach(this, flutterEngine)
        GozarReminderBridge.attach(this, flutterEngine)
        val telegram = GozarTelegramWebViewFactory(
            this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            GozarTelegramWebViewFactory.VIEW_TYPE, telegram)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        SystemVpnBridge.onActivityResult(this, requestCode, resultCode)
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
# Gozar has no TDLib, Telegram sign-in or private Telegram SOCKS process.
# This activity exists only in the standalone VPN build, never in news/cafe.
(activity.parent / 'GozarWebActivity.kt').write_bytes(
    (root / 'native/GozarWebActivity.kt').read_bytes()
)
(activity.parent / 'GozarTelegramWebView.kt').write_bytes(
    (root / 'native/GozarTelegramWebView.kt').read_bytes()
)
(activity.parent / 'GozarReminderBridge.kt').write_bytes(
    (root / 'native/GozarReminderBridge.kt').read_bytes()
)
internal = activity.parent / 'InternalTelegramProxyService.kt'
assert internal.is_file()
internal.unlink()
bridge = activity.parent / 'SystemVpnBridge.kt'
code = bridge.read_text()
# Remove only the Telegram SOCKS actions. Earlier builds accidentally deleted
# the intervening app/web launcher and icon MethodChannel handlers as well,
# causing all shortcuts to display but never open in the standalone APK.
begin = code.index('                    "startInternal" -> {')
end = code.index('                    "openShortcutApp" -> {', begin)
standalone_bridge = code[:begin] + code[end:]
assert '"startInternal" ->' not in standalone_bridge
assert '"stopInternal" ->' not in standalone_bridge
for method in ('openShortcutApp', 'openShortcutWeb', 'appIcon', 'installedApps'):
    assert f'"{method}" ->' in standalone_bridge, (
        f'Standalone Gozar lost the {method} native handler'
    )
assert 'InternalTelegramProxyService' not in standalone_bridge
bridge.write_text(standalone_bridge)
manifest = host / 'AndroidManifest.xml'
source = manifest.read_text()
source, count = re.subn(
    r'\s*<service\s+android:name="\.InternalTelegramProxyService"[\s\S]*?</service>',
    '', source, count=1,
)
assert count == 1, 'Unexpected native service manifest'
# Android alarms, permission consent and reboot recovery are for Gozar only.
source = source.replace('<application',
    '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
    '    <application', 1)
# Unexported internal browser for user-saved HTTPS shortcuts.
source = source.replace('</application>', '''
        <activity
            android:name=".GozarWebActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar" />
         <receiver android:name=".GozarReminderReceiver"
             android:exported="false" />
         <receiver android:name=".GozarReminderBootReceiver"
             android:enabled="true" android:exported="true">
             <intent-filter>
                 <action android:name="android.intent.action.BOOT_COMPLETED" />
                 <action android:name="android.intent.action.TIME_SET" />
                 <action android:name="android.intent.action.TIMEZONE_CHANGED" />
                 <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
             </intent-filter>
         </receiver>
    </application>''', 1)
manifest.write_text(source)
assert 'InternalTelegramProxyService' not in manifest.read_text()
assert 'BIND_VPN_SERVICE' in manifest.read_text()
print('Gozar: independent package, Xray VPN service only, no Telegram engine')
