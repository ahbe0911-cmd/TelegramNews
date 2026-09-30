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


  test('converts a compact wireguard share link to wg-quick format', () {
    const link =
        'wireguard://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D'
        '@vpn.example.com:51820/'
        '?publickey=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB%3D'
        '&address=10.10.0.2%2F32'
        '&mtu=1400'
        '&allowedips=0.0.0.0%2F0%2C%3A%3A%2F0'
        '&keepalive=25'
        '&dns=1.1.1.1%2C8.8.8.8'
        '&presharedkey=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC%3D'
        '#testwg';

    final config = validateWireGuardConfig(link);
    expect(config, contains('[Interface]'));
    expect(config, contains(
        'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='));
    expect(config, contains('Address = 10.10.0.2/32'));
    expect(config, contains('DNS = 1.1.1.1,8.8.8.8'));
    expect(config, contains('MTU = 1400'));
    expect(config, contains('[Peer]'));
    expect(config, contains('Endpoint = vpn.example.com:51820'));
    expect(config, contains('AllowedIPs = 0.0.0.0/0,::/0'));
    expect(config, contains('PersistentKeepalive = 25'));
    expect(config, contains('PresharedKey = '));
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
