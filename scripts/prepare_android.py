#!/usr/bin/env python3
"""Generate the Android host using the selected Flutter SDK, then configure it."""
import argparse, json, re, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--profile', choices=['modern', 'legacy'], default='modern')
args = parser.parse_args()
if (ROOT / 'android').exists():
    raise SystemExit('android/ already exists. Keep your configuration or remove the generated folder explicitly before regenerating.')
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['flutter','create','--no-pub','--platforms=android','--org=ir.channel','--project-name=telegram_news',tmp+'/host'], check=True)
    shutil.copytree(Path(tmp)/'host/android', ROOT/'android')
a = ROOT/'android'
if args.profile == 'legacy':
    shutil.copyfile(ROOT/'pubspec.legacy.yaml', ROOT/'pubspec.yaml')
    settings = a/'settings.gradle'
    s = settings.read_text()
    s = re.sub(r'id "com.android.application" version "[^"]+"', 'id "com.android.application" version "8.6.1"',s)
    s = re.sub(r'id "org.jetbrains.kotlin.android" version "[^"]+"', 'id "org.jetbrains.kotlin.android" version "1.9.24"',s)
    settings.write_text(s)
    wrapper = a/'gradle/wrapper/gradle-wrapper.properties'
    wrapper.write_text(re.sub(r'gradle-[\d.]+-(?:all|bin)\.zip','gradle-8.7-all.zip',wrapper.read_text()))
    (a/'app/build.gradle').write_text('''plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}
def keyProperties = new Properties()
def keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyProperties.load(new FileInputStream(keyFile))
android {
    namespace "ir.channel.telegram_news"
    compileSdk 35
    ndkVersion flutter.ndkVersion
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }
    kotlinOptions { jvmTarget = '17' }
    defaultConfig {
        applicationId "ir.channel.telegram_news"
        minSdk 21
        targetSdk 35
        versionCode flutter.versionCode
        versionName flutter.versionName
        multiDexEnabled true
    }
    signingConfigs {
        release {
            if (keyFile.exists()) {
                keyAlias keyProperties['keyAlias']
                keyPassword keyProperties['keyPassword']
                storeFile file(keyProperties['storeFile'])
                storePassword keyProperties['storePassword']
            }
        }
    }
    buildTypes {
        release {
            signingConfig keyFile.exists() ? signingConfigs.release : signingConfigs.debug
            minifyEnabled false
            shrinkResources false
        }
    }
}
flutter { source "../.." }
dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4' }
''')
else:
    build = a/'app/build.gradle.kts'
    if not build.exists():
        raise SystemExit('Flutter Android template changed: expected Kotlin Gradle file. Review bootstrap before continuing.')
    s = build.read_text()
    s = 'import java.util.Properties\nimport java.io.FileInputStream\n'+s
    s = s.replace('android {', '''val keyProperties = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyProperties.load(FileInputStream(keyFile))
android {''',1)
    s = re.sub(r'minSdk = .*', 'minSdk = 24',s)
    s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
    s = s.replace('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17')
    s = s.replace('buildTypes {', '''signingConfigs {
        create("release") {
            if (keyFile.exists()) {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }
    buildTypes {''',1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', '''signingConfig = signingConfigs.getByName(if (keyFile.exists()) "release" else "debug")
            isMinifyEnabled = false
            isShrinkResources = false''')
    s += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n'
    build.write_text(s)
manifest = a/'app/src/main/AndroidManifest.xml'
s = manifest.read_text().replace('<application','<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application',1)
s = s.replace('android:label="telegram_news"','android:label="نبض خبر" android:usesCleartextTraffic="false"')
manifest.write_text(s)
res = a/'app/src/main/res'
shutil.copytree(ROOT/'android-res', res, dirs_exist_ok=True)
# Integrate a native WebSocket↔SOCKS5 bridge in this app; no external app
# is required. Kotlin proxy classes are copied from ws_bridge/vendor by CI.
if args.profile == 'modern':
    native = list((a / 'app/src/main/kotlin').rglob('MainActivity.kt'))
    if len(native) != 1:
        raise SystemExit('Unexpected Flutter Kotlin activity layout')
    activity = native[0]
    source = activity.read_text()
    activity_match = re.search(
        r'class\s+MainActivity\s*:\s*FlutterActivity\(\)\s*(?:\{\s*\})?',
        source,
    )
    if activity_match is None:
        raise SystemExit('Unexpected Flutter activity template')
    source = source[:activity_match.start()] + '''private object EmbeddedWebSocketBridge {
    private var server: ProxyServer? = null

    @Synchronized fun start(): Boolean {
        if (server?.isRunning == true) return true
        val instance = ProxyServer(
            host = "127.0.0.1",
            port = 17881,
            // Include media and non-Premium datacenters, not just DC2 and DC4.
            dcOpt = mapOf(
                1 to "149.154.175.50",
                2 to "149.154.167.220",
                3 to "149.154.175.100",
                4 to "149.154.167.220",
                5 to "91.108.56.100"
            ),
            // No speculative TLS warmup: use CPU/battery only when required.
            poolSize = 0,
            bufKb = 128
        )
        server = instance
        instance.start()
        return true
    }

    @Synchronized fun stop() {
        server?.stop()
        server = null
    }
}

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ir.channel.telegram_tdnews/ws_internal"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> result.success(EmbeddedWebSocketBridge.start())
                    "stop" -> {
                        EmbeddedWebSocketBridge.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("INTERNAL_WS_ERROR", "Embedded WebSocket bridge failed", null)
            }
        }
    }
}''' + source[activity_match.end():]
    source = source.replace('import io.flutter.embedding.android.FlutterActivity',
'''import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flowseal.tgwsproxy.proxy.ProxyServer''')
    activity.write_text(source)

print('Android host prepared:', args.profile)
