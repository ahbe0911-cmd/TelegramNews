#!/usr/bin/env python3
"""Build the existing Gozar Flutter UI as an add-to-app Android module.

The native Forkgram source remains pinned at third_party/forkgram. This module
is generated under build/, not committed or installed as a second application.
Flutter AARs are linked INTO Forkgram's Android application at build time.
"""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
module = root / 'build' / 'gozar_module'
assert not module.exists(), 'Refusing to overwrite existing generated Flutter module'
subprocess.run([
    'flutter', 'create', '--template=module', '--org', 'ir.gozar.embed',
    '--project-name', 'gozar_module', str(module)
], check=True)
shutil.copytree(root / 'lib', module / 'lib', dirs_exist_ok=True)
# flutter build aar uses lib/main.dart; it does not support --target.
(module / 'lib' / 'main.dart').write_text(
    "import 'gozar_main.dart' as gozar;\nFuture<void> main() => gozar.main();\n",
    encoding='utf-8')
shutil.copytree(root / 'assets' / 'fonts', module / 'assets' / 'fonts',
                dirs_exist_ok=True)
(module / 'pubspec.yaml').write_text("""name: gozar_module
description: Gozar screens embedded in the native Forkgram host
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
flutter:
  uses-material-design: true
  fonts:
    - family: Vazirmatn
      fonts:
        - asset: assets/fonts/Vazirmatn-Regular.ttf
          weight: 400
        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
""", encoding='utf-8')
print('Generated Flutter add-to-app module:', module)
print('Entry point: lib/gozar_main.dart; library is packaged in the SAME APK.')
