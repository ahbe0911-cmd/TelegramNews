#!/usr/bin/env python3
"""Consume CI secrets without printing credentials or interpolating them in shell."""
import base64, json, os
from pathlib import Path
root = Path(__file__).resolve().parents[1]
raw = os.environ.get('GOOGLE_SERVICES_JSON','').strip()
config = {'API_BASE_URL':os.environ.get('API_BASE_URL',''), 'FIREBASE_ENABLED':bool(raw), 'APP_TITLE':os.environ.get('APP_TITLE') or 'نبض خبر'}
if config['API_BASE_URL'] and not config['API_BASE_URL'].startswith('https://'):
    raise SystemExit('API_BASE_URL must use HTTPS')
if raw:
    data = json.loads(raw)
    packages = [c['client_info']['android_client_info']['package_name'] for c in data['client']]
    if 'ir.channel.telegram_news' not in packages:
        raise SystemExit('Firebase package must be ir.channel.telegram_news')
    (root/'android/app/google-services.json').write_text(raw)
    kotlin = (root/'android/settings.gradle.kts').exists()
    settings = root/('android/settings.gradle.kts' if kotlin else 'android/settings.gradle')
    text = settings.read_text()
    marker = 'id("dev.flutter.flutter-plugin-loader")' if kotlin else 'id "dev.flutter.flutter-plugin-loader"'
    line = '    id("com.google.gms.google-services") version "4.4.2" apply false\n' if kotlin else '    id "com.google.gms.google-services" version "4.4.2" apply false\n'
    index = text.index(marker)
    text = text[:index]+line+text[index:]
    settings.write_text(text)
    app = root/('android/app/build.gradle.kts' if kotlin else 'android/app/build.gradle')
    plugin = 'id("com.google.gms.google-services")' if kotlin else 'id "com.google.gms.google-services"'
    app.write_text(app.read_text().replace('plugins {','plugins {\n    '+plugin,1))
key = os.environ.get('KEYSTORE_BASE64','')
if key:
    (root/'android/app/release.jks').write_bytes(base64.b64decode(key, validate=True))
    def prop(value):
        return value.replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r').replace('=','\\=').replace(':','\\:').replace(' ','\\ ')
    values = {'storeFile':'release.jks','storePassword':os.environ['KEYSTORE_PASSWORD'],'keyPassword':os.environ['KEY_PASSWORD'],'keyAlias':os.environ['KEY_ALIAS']}
    (root/'android/key.properties').write_text('\n'.join(k+'='+prop(v) for k,v in values.items()))
(root/'config.json').write_text(json.dumps(config, ensure_ascii=False))
print('Build mode:', 'connected' if raw else 'demo without push', '| signing:', 'release key' if key else 'test key')
