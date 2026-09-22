import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/td_system_vpn.dart';

const sampleId = 'b831381d-6324-4d53-ad4f-8cda48b30811';

String makeVmess(Map<String, Object?> settings) =>
    'vmess://' + base64Url.encode(utf8.encode(jsonEncode(settings))).replaceAll('=', '');

Map<String, dynamic> config(String link) =>
    Map<String, dynamic>.from(jsonDecode(buildFullDeviceXrayConfig(link)) as Map);

Map<String, dynamic> outbound(String link) =>
    Map<String, dynamic>.from((config(link)['outbounds'] as List).first as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installed Android shortcuts keep their selected launcher alias',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'installedApps') {
        return [
          {
            'package': 'com.example.installed',
            'label': 'برنامه من',
            'component': 'com.example.installed.LauncherAlias',
          },
        ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemVpnBridge.channel, null));
    final installed = await SystemVpnBridge.installedApps();
    expect(installed.single['component'],
        'com.example.installed.LauncherAlias');
    expect(installed.single['package'], 'com.example.installed');
  });

  test('VMess share link decodes base64url with missing padding; WS + TLS',
      () {
    final link = makeVmess({
      'v': '2',
      'ps': 'sample profile',
      'add': 'vpn.example.org',
      'port': '443',
      'id': sampleId,
      'aid': '0',
      'scy': 'auto',
      'net': 'ws',
      'host': 'cdn.example.org',
      'path': '/vmess',
      'tls': 'tls',
      'sni': 'cdn.example.org',
      'fp': 'chrome',
    });
    final result = config(link);
    expect((result['inbounds'] as List).first['protocol'], 'tun');
    final proxy = outbound(link);
    expect(proxy['protocol'], 'vmess');
    expect(proxy['tag'], 'proxy');
    final target = (proxy['settings']['vnext'] as List).first;
    expect(target['address'], 'vpn.example.org');
    expect(target['port'], 443);
    final user = (target['users'] as List).first;
    expect(user['id'], sampleId);
    expect(user['alterId'], 0);
    expect(user['security'], 'auto');
    final stream = proxy['streamSettings'];
    expect(stream['network'], 'ws');
    expect(stream['security'], 'tls');
    expect(stream['tlsSettings']['serverName'], 'cdn.example.org');
    expect(stream['tlsSettings']['allowInsecure'], isFalse);
    expect(stream['wsSettings']['path'], '/vmess');
    expect(stream['wsSettings']['headers']['Host'], 'cdn.example.org');
  });

  test('VMess TCP without TLS and legacy alterId is parsed', () {
    final profile = {
      'add': '198.51.100.2',
      'port': 80,
      'id': sampleId,
      'aid': 2,
      'net': 'tcp',
      'tls': '',
    };
    final link = 'vmess://' + base64.encode(utf8.encode(jsonEncode(profile)));
    final proxy = outbound(link);
    expect(proxy['streamSettings']['network'], 'tcp');
    expect(proxy['streamSettings']['security'], 'none');
    expect((proxy['settings']['vnext'] as List).first['users'].first['alterId'], 2);
  });

  test('VMess gRPC and H2 include their transport-specific parameters', () {
    final base = {
      'add': 'example.org', 'port': '443',
      'id': sampleId, 'aid': '0', 'tls': 'tls',
    };
    final grpc = outbound(makeVmess({
      ...base, 'net': 'grpc', 'path': 'grpcService',
    }));
    expect(grpc['streamSettings']['grpcSettings']['serviceName'], 'grpcService');
    final http = outbound(makeVmess({
      ...base, 'net': 'h2', 'host': 'cdn.example.org',
      'path': '/h2',
    }));
    expect(http['streamSettings']['network'], 'http');
    expect(http['streamSettings']['httpSettings']['host'], ['cdn.example.org']);
    expect(http['streamSettings']['httpSettings']['path'], '/h2');
  });

  test('Invalid or incomplete VMess links fail before requesting Android VPN',
      () {
    expect(() => buildFullDeviceXrayConfig('vmess://'), throwsFormatException);
    expect(() => buildFullDeviceXrayConfig('vmess://not-base64!'),
        throwsFormatException);
    expect(() => buildFullDeviceXrayConfig(makeVmess({
      'add': 'example.org', 'port': 443, 'id': 'invalid',
    })), throwsFormatException);
    expect(() => buildFullDeviceXrayConfig(makeVmess({
      'add': 'example.org', 'port': 443,
      'id': sampleId, 'net': 'unsupported',
    })), throwsFormatException);
  });

  test('Existing VLESS/Trojan/JSON support is not replaced by VMess', () {
    expect(outbound('vless://' + sampleId +
        '@example.org:443?security=tls')['protocol'], 'vless');
    expect(outbound('trojan://secret@example.org:443')['protocol'], 'trojan');
    expect(outbound(jsonEncode({
      'outbounds': [
        {'tag': 'user-selected', 'protocol': 'vmess',
         'settings': {'vnext': []}},
      ],
    }))['protocol'], 'vmess');
  });
}
