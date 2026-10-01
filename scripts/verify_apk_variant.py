"""Verify the delivered APK, not just the configuration used to build it."""
from pathlib import Path
import os, subprocess, sys, zipfile

variant = sys.argv[1]
assert variant in ('news', 'cafenet', 'dual', 'gozar')
package = ('ir.channel.gozar_vpn' if variant == 'gozar' else
           'ir.channel.telegram_dual' if variant == 'dual' else
           'ir.channel.telegram_cafenet' if variant == 'cafenet' else
           'ir.channel.telegram_tdnews')
label = 'گذر' if variant == 'gozar' else 'نبض خبر و کافی‌نت' if variant == 'dual' else 'کافی‌نت' if variant == 'cafenet' else 'نبض خبر'
apk = Path('build/app/outputs/flutter-apk/app-release.apk')
aapt = next(Path(os.environ['ANDROID_HOME']).glob('build-tools/*/aapt'))
badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True)
assert f"package: name='{package}'" in badging
assert f"application-label:'{label}'" in badging
manifest = subprocess.check_output(
    [str(aapt), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'],
    text=True
)
with zipfile.ZipFile(apk) as archive:
    names = set(archive.namelist())
    if variant == 'gozar':
        assert 'android.permission.BIND_VPN_SERVICE' not in manifest
        assert 'android.net.VpnService' not in manifest
        assert 'GozarVpnService' not in manifest
        assert 'SystemVpnService' not in manifest
        assert 'InternalTelegramProxyService' not in manifest
        assert 'android.permission.QUERY_ALL_PACKAGES' in manifest
        assert 'lib/arm64-v8a/libtdjson.so' not in names, 'Gozar must not bundle TDLib'
        assert not any(
            'libv2ray' in entry.lower() or
            'libgojni.so' in entry.lower() or
            'libwg-go.so' in entry.lower()
            for entry in names
        ), 'Gozar must not bundle any VPN tunnel engine'
        print('APK verified: Gozar launcher + notes, VPN fully removed')
        sys.exit(0)
    assert 'android.permission.BIND_VPN_SERVICE' not in manifest
    assert 'SystemVpnService' not in manifest
    assert 'InternalTelegramProxyService' not in manifest
    assert not any('libv2ray' in entry.lower() or 'libgojni.so' in entry.lower()
                   for entry in names), 'VPN engine must not be in news/cafenet'
    native = archive.read('lib/arm64-v8a/libtdjson.so')
    assert native[:4] == b'\x7fELF'
    assert int.from_bytes(native[18:20], 'little') == 183, 'Not AArch64'
    assert b'td_json_client_create' in native, 'Missing TDLib JSON ABI'
    # Flutter may strip additional ELF sections, so compare .text separately.
    def section(data, wanted):
        import struct
        offset = struct.unpack_from('<Q', data, 40)[0]
        size, count, names_index = struct.unpack_from('<HHH', data, 58)
        name_header = offset + size * names_index
        names_offset = struct.unpack_from('<Q', data, name_header + 24)[0]
        for index in range(count):
            pos = offset + size * index
            name = names_offset + struct.unpack_from('<I', data, pos)[0]
            end = data.index(b'\0', name)
            if data[name:end] == wanted:
                start, length = struct.unpack_from('<QQ', data, pos + 24)
                return data[start:start + length]
        raise AssertionError('ELF section missing')
    assert section(native, b'.text') == section(Path('native-tdlib/libtdjson.so').read_bytes(), b'.text'), 'Old TDLib packaged'
print(f'APK verified: {label}, {package}, current ARM64 Telegram engine')
