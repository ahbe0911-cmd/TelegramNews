#!/usr/bin/env python3
"""Brand generated Android hosts without changing their shared implementation."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('variant', choices=['news', 'cafenet', 'gozar'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
cafe = args.variant == 'cafenet'
gozar = args.variant == 'gozar'
package = ('ir.channel.gozar_vpn' if gozar else
           'ir.channel.telegram_cafenet' if cafe else 'ir.channel.telegram_tdnews')
label = 'گذر' if gozar else 'کافی‌نت' if cafe else 'نبض خبر'
folder = 'Gozar' if gozar else 'Cafenet' if cafe else 'NabzKhabar'
gradle = root / 'android/app/build.gradle.kts'
source, count = re.subn(r'applicationId = "[^"]+"', f'applicationId = "{package}"', gradle.read_text())
assert count == 1, 'Expected one application ID'
gradle.write_text(source)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
source, count = re.subn(r'android:label="[^"]+"', f'android:label="{label}"', manifest.read_text())
assert count == 1
manifest.write_text(source)
activity = next((root / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
activity.write_text(activity.read_text().replace('"/NabzKhabar"', f'"/{folder}"'))
res = root / 'android/app/src/main/res'
color = '#087E70' if gozar else '#7043C6' if cafe else '#0866DC'
# Vector assets stay crisp on A54 and support Android adaptive launcher masks.
paths = '''<path android:fillColor="#FFFFFFFF" android:pathData="M28,31 L80,31 Q84,31 84,35 L84,67 Q84,71 80,71 L59,71 L59,77 L70,77 L70,81 L38,81 L38,77 L49,77 L49,71 L28,71 Q24,71 24,67 L24,35 Q24,31 28,31 Z"/>
<path android:fillColor="COLOR" android:pathData="M30,37 L78,37 L78,64 L30,64 Z"/>
<path android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="3" android:strokeLineCap="round" android:pathData="M43,44 L37,50 L43,56 M65,44 L71,50 L65,56 M57,43 L51,57"/>''' if cafe else '''<path android:fillColor="#FFFFFFFF" android:pathData="M28,27 L73,27 Q78,27 78,32 L78,77 Q78,81 73,81 L28,81 Q24,81 24,77 L24,32 Q24,27 28,27 Z M80,37 L85,37 L85,76 Q85,81 80,81 Z"/>
<path android:fillColor="COLOR" android:pathData="M32,36 L69,36 L69,41 L32,41 Z M32,64 L69,64 L69,68 L32,68 Z M32,73 L57,73 L57,76 L32,76 Z"/>
<path android:fillColor="#00000000" android:strokeColor="COLOR" android:strokeWidth="3" android:strokeLineJoin="round" android:pathData="M32,53 L42,53 L47,46 L53,60 L58,51 L69,51"/>'''
if gozar:
    # A separate green shield icon for the VPN application.
    paths = '''<path android:fillColor="#FFFFFFFF" android:pathData="M54,19 L83,31 L83,52 Q83,72 54,89 Q25,72 25,52 L25,31 Z"/>
<path android:fillColor="COLOR" android:pathData="M54,28 L75,36 L75,52 Q75,66 54,78 Q33,66 33,52 L33,36 Z"/>
<path android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="5" android:strokeLineCap="round" android:strokeLineJoin="round" android:pathData="M41,53 L51,62 L68,44"/>'''
paths = paths.replace('COLOR', color)
def vector(background):
    bg = f'<path android:fillColor="{color}" android:pathData="M0,0 L108,0 L108,108 L0,108 Z"/>' if background else ''
    return f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">{bg}{paths}</vector>'
for density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']:
    icon = res / f'mipmap-{density}/ic_launcher.png'
    if icon.exists(): icon.unlink()
(res / 'mipmap-anydpi').mkdir(exist_ok=True)
(res / 'mipmap-anydpi/ic_launcher.xml').write_text(vector(True))
(res / 'drawable/ic_brand_foreground.xml').write_text(vector(False))
(res / 'values/brand_colors.xml').write_text(f'<resources><color name="brand_background">{color}</color></resources>')
(res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/brand_background"/><foreground android:drawable="@drawable/ic_brand_foreground"/></adaptive-icon>''')
print(f'Configured {args.variant}: {package}, {label}')
