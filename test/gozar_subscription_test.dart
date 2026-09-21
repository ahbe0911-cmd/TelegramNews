import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/gozar_subscription.dart';

const id = 'b831381d-6324-4d53-ad4f-8cda48b30811';

String vmess(String name) => 'vmess://' + base64.encode(utf8.encode(jsonEncode({
  'v': '2', 'ps': name, 'add': 'a.example', 'port': '443',
  'id': id, 'aid': '0', 'net': 'tcp', 'tls': 'tls',
})));

void main() {
  test('plain and base64 subscriptions keep supported unique nodes', () {
    final body = [
      vmess('alpha'),
      'vless://$id@b.example:443?security=tls#beta',
      'trojan://secret@c.example:443#gamma',
      'ss://unsupported',
    ].join('\n');
    final plain = parseGozarSubscription(body);
    final encoded = base64.encode(utf8.encode(body));
    final packed = parseGozarSubscription(encoded);
    expect(plain, hasLength(3));
    expect(packed, hasLength(3));
    expect(plain.map((node) => node.name), containsAll(['beta', 'gamma']));
  });

  test('invalid subscription is rejected', () {
    expect(() => parseGozarSubscription('not a subscription'),
        throwsFormatException);
  });

  test('best node ignores failures and chooses lowest measured latency',
      () async {
    final links = ['slow', 'dead', 'fast'];
    final result = await chooseBestGozarNode(links,
        probe: (link) async => {'slow': 180, 'dead': null, 'fast': 42}[link]);
    expect(result?.index, 2);
    expect(result?.latencyMs, 42);
  });
}
