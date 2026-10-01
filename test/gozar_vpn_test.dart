import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/gozar_vpn.dart';

const uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

String vmess() => 'vmess://' + base64.encode(utf8.encode(jsonEncode({
  'v': '2',
  'ps': 'vmess',
  'add': 'vmess.example',
  'port': '443',
  'id': uuid,
  'aid': '0',
  'net': 'ws',
  'path': '/ws',
  'host': 'cdn.example',
  'tls': 'tls',
})));

void main() {
  test('Xray config accepts VMess and creates a TUN inbound', () {
    final raw = buildGozarXrayConfig(vmess());
    final config = jsonDecode(raw) as Map<String, dynamic>;
    final inbounds = config['inbounds'] as List;
    final outbounds = config['outbounds'] as List;
    expect((inbounds.first as Map)['protocol'], 'tun');
    expect((outbounds.first as Map)['protocol'], 'vmess');
    expect((outbounds.first as Map)['tag'], 'proxy');
  });

  test('Xray config accepts VLESS REALITY and XHTTP', () {
    final link =
        'vless://$uuid@reality.example:443'
        '?security=reality&encryption=none'
        '&type=xhttp&mode=auto&path=%2Fapi'
        '&sni=www.example.com&fp=chrome'
        '&pbk=0123456789012345678901234567890123456789012'
        '&sid=abcd#reality';
    final raw = buildGozarXrayConfig(link);
    final config = jsonDecode(raw) as Map<String, dynamic>;
    final outbound =
        (config['outbounds'] as List).first as Map<String, dynamic>;
    expect(outbound['protocol'], 'vless');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['security'], 'reality');
    expect(stream['network'], 'xhttp');
    expect((stream['xhttpSettings'] as Map)['mode'], 'auto');
  });

  test('Xray config accepts Trojan TLS', () {
    const link =
        'trojan://secret@trojan.example:443'
        '?security=tls&type=grpc&serviceName=edge#trojan';
    final raw = buildGozarXrayConfig(link);
    final config = jsonDecode(raw) as Map<String, dynamic>;
    final outbound =
        (config['outbounds'] as List).first as Map<String, dynamic>;
    expect(outbound['protocol'], 'trojan');
    expect(
      ((outbound['streamSettings'] as Map)['grpcSettings'] as Map)
          ['serviceName'],
      'edge',
    );
  });

  test('Xray config accepts SIP002 Shadowsocks', () {
    final credentials = base64Url
        .encode(utf8.encode('aes-128-gcm:strong-password'))
        .replaceAll('=', '');
    final link = 'ss://' + credentials + '@ss.example:8388#shadow';
    final raw = buildGozarXrayConfig(link);
    final config = jsonDecode(raw) as Map<String, dynamic>;
    final outbound =
        (config['outbounds'] as List).first as Map<String, dynamic>;
    expect(outbound['protocol'], 'shadowsocks');
    final settings = outbound['settings'] as Map;
    expect(settings['address'], 'ss.example');
    expect(settings['port'], 8388);
    expect(settings['method'], 'aes-128-gcm');
  });

  test('Iranian domains have direct routing with sniffing', () {
    final config =
        jsonDecode(buildGozarXrayConfig(vmess())) as Map<String, dynamic>;
    final inbound =
        (config['inbounds'] as List).first as Map<String, dynamic>;
    expect((inbound['sniffing'] as Map)['enabled'], isTrue);

    final outbounds = config['outbounds'] as List;
    expect(
      outbounds.whereType<Map>().any((item) => item['tag'] == 'direct'),
      isTrue,
    );

    final rules = (config['routing'] as Map)['rules'] as List;
    final direct = rules.whereType<Map>()
        .firstWhere((item) => item['outboundTag'] == 'direct');
    expect(
      (direct['domain'] as List),
      contains('regexp:.*\\.ir\$'),
    );
    expect((direct['domain'] as List), contains('domain:bale.ai'));
    expect((direct['domain'] as List), contains('domain:eitaa.com'));
  });

  test('display protocol label stays compact', () {
    expect(gozarProtocolLabel('vless://x'), 'VLESS');
    expect(gozarProtocolLabel('vmess://x'), 'VMess');
    expect(gozarProtocolLabel('trojan://x'), 'Trojan');
    expect(gozarProtocolLabel('ss://x'), 'Shadowsocks');
  });
}
