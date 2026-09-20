import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public channel links are normalized without accepting invites', () {
    expect(parsePublicUsername('@ExampleNews'), 'ExampleNews');
    expect(parsePublicUsername('https://t.me/ExampleNews/123'), 'ExampleNews');
    expect(parsePublicUsername('https://t.me/+secretinvite'), isNull);
    expect(parsePublicUsername('https://example.com/wrong'), isNull);
    expect(parsePublicUsername('1234'), isNull);
  });

  test('stored sources restore after a controller restart', () async {
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"Example News"}',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = TdNewsController(prefs);
    expect(controller.sources.keys, contains(-100123456));
    expect(controller.sources[-100123456]?.username, 'ExampleNews');
    controller.dispose();
  });

  test('TDLib message ids convert to public Telegram links', () {
    final post = NewsPost(
        -100123456, 123 * 1048576, 1700000000, 'News',
        'ExampleNews', 'متن خبر', null, null);
    expect(post.link, 'https://t.me/ExampleNews/123');
  });
}
