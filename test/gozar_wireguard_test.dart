import 'package:flutter_test/flutter_test.dart';

import '../lib/td_system_vpn.dart';

void main() {
  test('accepts a complete WireGuard client profile', () {
    const config = '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.10.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
''';
    expect(validateWireGuardConfig(config), contains('[Peer]'));
  });

  test('rejects a WireGuard profile without endpoint', () {
    const config = '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.10.0.2/32

[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 0.0.0.0/0
''';
    expect(() => validateWireGuardConfig(config), throwsFormatException);
  });

  test('rejects non WireGuard text', () {
    expect(() => validateWireGuardConfig('vmess://example'),
        throwsFormatException);
  });
}
