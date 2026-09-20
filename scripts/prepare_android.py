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

# File downloads use Android MediaStore so the saved file is available in
# Downloads/NabzKhabar (on Android 10+). Copy off the UI thread.
if args.profile == 'modern':
    activities = list((a / 'app/src/main/kotlin').rglob('MainActivity.kt'))
    if len(activities) != 1:
        raise SystemExit('Unexpected Flutter Android activity layout')
    activity = activities[0]
    native = activity.read_text()
    anchor = 'class MainActivity : FlutterActivity()'
    if anchor not in native:
        raise SystemExit('Flutter Activity template changed; inspect generated activity')
    native = native.replace(anchor, r'''class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "ir.channel.telegram_tdnews/downloads").setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val title = call.argument<String>("name")
            val mime = call.argument<String>("mime") ?: "application/octet-stream"
            if (path.isNullOrBlank() || title.isNullOrBlank()) {
                result.error("BAD_FILE", "The file name or path is missing", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    val file = File(path)
                    if (!file.isFile) throw IllegalStateException("Downloaded file is missing")
                    val safe = title.replace(Regex("[/\\\\\\u0000-\\u001f]"), "_").take(100)
                    val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, safe)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            put(MediaStore.MediaColumns.RELATIVE_PATH,
                                Environment.DIRECTORY_DOWNLOADS + "/NabzKhabar")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Downloads storage unavailable")
                        try {
                            val stream = contentResolver.openOutputStream(uri)
                                ?: throw IllegalStateException("Cannot write download")
                            stream.use { output ->
                                FileInputStream(file).use { input ->
                                    input.copyTo(output, bufferSize = 65536)
                                }
                            }
                            contentResolver.update(uri, ContentValues().apply {
                                put(MediaStore.MediaColumns.IS_PENDING, 0)
                            }, null, null)
                            uri.toString()
                        } catch (error: Exception) {
                            contentResolver.delete(uri, null, null)
                            throw error
                        }
                    } else {
                        val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                            ?: throw IllegalStateException("Storage unavailable")
                        val output = File(directory, safe)
                        FileInputStream(file).use { input ->
                            output.outputStream().use { dest ->
                                input.copyTo(dest, bufferSize = 65536)
                            }
                        }
                        output.absolutePath
                    }
                    runOnUiThread { result.success(saved) }
                } catch (_: Exception) {
                    runOnUiThread {
                        result.error("SAVE_FAILED", "Download could not be saved", null)
                    }
                }
            }.start()
        }
    }
}''', 1)
    native = native.replace(
        'import io.flutter.embedding.android.FlutterActivity',
        '''import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream''', 1)
    activity.write_text(native)
