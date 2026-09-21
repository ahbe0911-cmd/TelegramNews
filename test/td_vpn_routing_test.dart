import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      calls.add(call);
      if (call.method == 'installedApps') {
        return [
          {'label': 'Browser', 'package': 'com.example.browser'},
          {'label': 'Chat', 'package': 'com.example.chat'},
        ];
      }
      if (call.method == 'status') {
        return {'stage': 'running', 'detail': 'Android TUN is active'};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVpnBridge.channel, null);
  });

  test('only selected apps are sent to Android VPN with configuration', () async {
    await SystemVpnBridge.start('{"inbounds":[]}', mode: 'selected',
        packages: ['com.example.browser']);
    expect(calls.single.method, 'start');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['mode'], 'selected');
    expect(args['packages'], ['com.example.browser']);
    expect(args['config'], '{"inbounds":[]}');
  });

  test('all-app mode remains default', () async {
    await SystemVpnBridge.start('{"inbounds":[]}');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['mode'], 'all');
    expect(args['packages'], isEmpty);
  });

  test('Android launchable app list maps labels and package IDs', () async {
    final apps = await SystemVpnBridge.installedApps();
    expect(apps, [
      {'label': 'Browser', 'package': 'com.example.browser'},
      {'label': 'Chat', 'package': 'com.example.chat'},
    ]);
    expect(calls.single.method, 'installedApps');
  });

  test('refresh reads native VPN status and stop calls native service', () async {
    expect((await SystemVpnBridge.status())['stage'], 'running');
    await SystemVpnBridge.stop();
    expect(calls.map((call) => call.method), ['status', 'stop']);
  });
}
