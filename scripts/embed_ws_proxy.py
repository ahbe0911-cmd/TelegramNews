#!/usr/bin/env python3
"""Copy a pinned, MIT-licensed native MTProto WS implementation into Flutter's generated host.

This script deliberately fails closed if the upstream snapshot or host layout changed.
The upstream repo is checked out at a fixed commit by the release workflow.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
upstream = root / "third_party" / "tgwsproxy_src"
src = upstream / "app/src/main/java/dev/minios/tgwsproxy"
assert (upstream / "LICENSE").exists(), "Pinned upstream source was not checked out"
assert "MIT License" in (upstream / "LICENSE").read_text(), "Unexpected upstream license"
host = root / "android/app/src/main/kotlin"
activities = list(host.rglob("MainActivity.kt"))
assert len(activities) == 1, "Unexpected Flutter Android activity layout"
activity = activities[0]
source = activity.read_text()
marker = "super.configureFlutterEngine(flutterEngine)"
assert source.count(marker) == 1
source = source.replace(marker, marker + "\n        EmbeddedProxyManager.attach(this, flutterEngine)", 1)
activity.write_text(source)
shutil.copyfile(root / "native/EmbeddedProxyManager.kt", activity.parent / "EmbeddedProxyManager.kt")

for path in (src / "proxy").glob("*.kt"):
    target = host / "dev/minios/tgwsproxy/proxy" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)

logger = (src / "diagnostics/DiagnosticLogger.kt").read_text()
assert "import dev.minios.tgwsproxy.BuildConfig" in logger
logger = logger.replace("import dev.minios.tgwsproxy.BuildConfig\n", "")
assert "BuildConfig.VERSION_NAME" in logger and "BuildConfig.VERSION_CODE" in logger
logger = logger.replace("BuildConfig.VERSION_NAME", '"embedded"')
logger = logger.replace("BuildConfig.VERSION_CODE", "1")
logger = logger.replace("BuildConfig.DEBUG", "false")
assert "BuildConfig." not in logger
diagnostics = host / "dev/minios/tgwsproxy/diagnostics/DiagnosticLogger.kt"
diagnostics.parent.mkdir(parents=True, exist_ok=True)
diagnostics.write_text(logger)

gradle = root / "android/app/build.gradle.kts"
text = gradle.read_text()
assert "coreLibraryDesugaring(" in text
text += """
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
"""
gradle.write_text(text)
manifest = root / "android/app/src/main/AndroidManifest.xml"
text = manifest.read_text()
assert 'android.permission.INTERNET' in text
assert 'android.permission.ACCESS_NETWORK_STATE' not in text
text = text.replace('<application', '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <application', 1)
manifest.write_text(text)
print("Embedded MIT-licensed local-only TG WS Proxy engine into Android host")
