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
    - family: Rooznameh
      fonts:
        - asset: assets/fonts/Rooznameh.ttf
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
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        SystemVpnBridge.onActivityResult(this, requestCode, resultCode)
    }
}
''')
# Gozar has no TDLib, Telegram sign-in or private Telegram SOCKS process.
internal = activity.parent / 'InternalTelegramProxyService.kt'
assert internal.is_file()
internal.unlink()
bridge = activity.parent / 'SystemVpnBridge.kt'
code = bridge.read_text()
begin = code.index('                    "startInternal" -> {')
end = code.index('                    "installedApps" -> {', begin)
bridge.write_text(code[:begin] + code[end:])
manifest = host / 'AndroidManifest.xml'
source = manifest.read_text()
source, count = re.subn(
    r'\s*<service\s+android:name="\.InternalTelegramProxyService"[\s\S]*?</service>',
    '', source, count=1,
)
assert count == 1, 'Unexpected native service manifest'
manifest.write_text(source)
assert 'InternalTelegramProxyService' not in manifest.read_text()
assert 'BIND_VPN_SERVICE' in manifest.read_text()
print('Gozar: independent package, Xray VPN service only, no Telegram engine')
