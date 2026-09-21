import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const exampleId = 'b831381d-6324-4d53-ad4f-8cda48b30811';
  final link = 'vmess://' + base64Url.encode(utf8.encode(jsonEncode({
    'add': 'example.org', 'port': '443', 'id': exampleId,
    'aid': '0', 'net': 'ws', 'path': '/telegram',
    'host': 'cdn.example.org', 'tls': 'tls',
  }))).replaceAll('=', '');

  test('dedicated SOCKS-only core uses same server with no TUN fd', () {
    final phoneConfig = jsonDecode(buildFullDeviceXrayConfig(link)) as Map;
    final separate = jsonDecode(buildInternalTelegramXrayConfig(
        jsonEncode(phoneConfig))) as Map;
    final phoneInbound = phoneConfig['inbounds'] as List;
    final internalInbound = separate['inbounds'] as List;
    expect(phoneInbound.first['protocol'], 'tun');
    expect(internalInbound.length, 1);
    expect(internalInbound.first['protocol'], 'socks');
    expect(internalInbound.first['listen'], '127.0.0.1');
    expect(internalInbound.first['port'], 10809);
    expect(internalInbound.where((inbound) => inbound['protocol'] == 'tun'),
        isEmpty);
    expect(separate['outbounds'], phoneConfig['outbounds']);
    expect(separate['routing']['rules'][0]['outboundTag'], 'proxy');
  });

  test('separate config refuses missing outbound before launching service', () {
    expect(() => buildInternalTelegramXrayConfig('{"outbounds":[]}'),
        throwsFormatException);
    expect(() => buildInternalTelegramXrayConfig('[]'),
        throwsFormatException);
  });

  test('start and stop independent native SOCKS service use distinct methods',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemVpnBridge.channel, null);
    });
    final config = buildInternalTelegramXrayConfig(
        buildFullDeviceXrayConfig(link));
    await SystemVpnBridge.startInternal(config);
    await SystemVpnBridge.stopInternal();
    expect(calls.map((call) => call.method), ['startInternal', 'stopInternal']);
    expect((calls.first.arguments as Map)['config'], config);
  });
}
