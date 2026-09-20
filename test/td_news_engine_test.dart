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
  test('video and PDF posts keep their downloadable TDLib file IDs', () async {
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"Example News"}',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final news = TdNewsController(prefs);
    news.record({
      'chat_id': -100123456, 'id': 105 * 1048576, 'date': 1700000001,
      'content': {
        '@type': 'messageVideo',
        'video': {'video': {'id': 3001}},
        'caption': {'text': 'ویدئوی خبری'},
      },
    });
    final video = news.feed.single;
    expect(video.mediaKind, 'video');
    expect(video.mediaFileId, 3001);
    expect(video.body, 'ویدئوی خبری');

    news.record({
      'chat_id': -100123456, 'id': 106 * 1048576, 'date': 1700000002,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': 'report.PDF', 'document': {'id': 3002},
        },
        'caption': {'text': 'گزارش تازه'},
      },
    });
    final document = news.feed.first;
    expect(document.mediaKind, 'pdf');
    expect(document.mediaFileId, 3002);
    expect(document.fileName, 'report.PDF');
    expect(document.body, 'گزارش تازه');

    news.dispose();
  });

}
