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

    news.record({
      'chat_id': -100123456, 'id': 107 * 1048576, 'date': 1700000003,
      'content': {
        '@type': 'messageVideoNote',
        'video_note': {'video': {'id': 3003}},
      },
    });
    final note = news.feed.first;
    expect(note.mediaKind, 'video');
    expect(note.mediaFileId, 3003);
    expect(note.body, 'ویدئو');

    news.record({
      'chat_id': -100123456, 'id': 108 * 1048576, 'date': 1700000004,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': 'clip.mp4',
          'mime_type': 'video/mp4',
          'document': {'id': 3004},
        },
        'caption': {'text': 'فیلم خبر'},
      },
    });
    final mp4 = news.feed.first;
    expect(mp4.mediaKind, 'video');
    expect(mp4.mediaFileId, 3004);
    expect(mp4.body, 'فیلم خبر');

    news.record({
      'chat_id': -100123456, 'id': 109 * 1048576, 'date': 1700000005,
      'content': {
        '@type': 'messageAnimation',
        'animation': {
          'mime_type': 'video/mp4',
          'animation': {'id': 3005},
        },
      },
    });
    final animation = news.feed.first;
    expect(animation.mediaKind, 'video');
    expect(animation.mediaFileId, 3005);

    news.record({
      'chat_id': -100123456, 'id': 110 * 1048576, 'date': 1700000006,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': 'newspaper.pdf',
          'mime_type': 'application/pdf',
          'document': {'id': 3006},
        },
      },
    });
    final pdf = news.feed.first;
    expect(pdf.mediaKind, 'pdf');
    expect(pdf.mediaFileId, 3006);
    expect(pdf.body, 'newspaper.pdf');

    news.dispose();
  });

  test('bookmarks persist independently of the live feed and can be removed', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = TdNewsController(preferences);
    final post = NewsPost(
      -100123456, 120 * 1048576, 1700000000, 'News',
      'ExampleNews', 'گزارش ذخیره‌شده', null, null,
      mediaKind: 'pdf', mediaFileId: 4999, fileName: 'report.pdf',
    );
    expect(controller.isSaved(post), isFalse);
    await controller.toggleSaved(post);
    expect(controller.isSaved(post), isTrue);
    expect(controller.savedFeed.single.body, 'گزارش ذخیره‌شده');
    controller.dispose();

    final restored = TdNewsController(preferences);
    expect(restored.savedFeed, hasLength(1));
    expect(restored.savedFeed.single.link, post.link);
    expect(restored.savedFeed.single.mediaKind, 'pdf');
    expect(restored.savedFeed.single.mediaFileId, 4999);
    await restored.toggleSaved(restored.savedFeed.single);
    expect(restored.savedFeed, isEmpty);
    restored.dispose();

    final reopened = TdNewsController(preferences);
    expect(reopened.savedFeed, isEmpty);
    reopened.dispose();
  });

}
