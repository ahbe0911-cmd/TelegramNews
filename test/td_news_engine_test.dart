import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';
import 'package:telegram_news/td_mtproto_proxy.dart';

void main() {
  test('MTProto deep links parse without accepting SOCKS or bad secrets', () {
    const secret = '0123456789abcdef0123456789abcdef';
    final one = parseMtprotoProxyLink(
        'tg://proxy?server=proxy.example.org&port=443&secret=$secret');
    expect(one.server, 'proxy.example.org');
    expect(one.port, 443);
    expect(one.secret, secret);
    final two = parseMtprotoProxyLink(
        'https://t.me/proxy?server=1.2.3.4&port=8443&secret=dd$secret');
    expect(two.server, '1.2.3.4');
    expect(two.port, 8443);
    expect(two.secret, 'dd$secret');
    expect(() => parseMtprotoProxyLink('tg://socks?server=x&port=80'),
        throwsFormatException);
    expect(() => parseMtprotoProxyLink(
        'tg://proxy?server=host&port=0&secret=$secret'), throwsFormatException);
    expect(() => parseMtprotoProxyLink(
        'tg://proxy?server=host&port=443&secret=bad'), throwsFormatException);
  });


  TestWidgetsFlutterBinding.ensureInitialized();

  test('public channel links are normalized without accepting invites', () {
    expect(parsePublicUsername('@ExampleNews'), 'ExampleNews');
    expect(parsePublicUsername('https://t.me/ExampleNews/123'), 'ExampleNews');
    expect(parsePublicUsername('https://t.me/+secretinvite'), isNull);
    expect(parsePublicUsername('https://example.com/wrong'), isNull);
    expect(parsePublicUsername('1234'), isNull);
  });

  test('new and legacy text previews retain playable video and caption', () async {
    SharedPreferences.setMockInitialValues({});
    final news = TdNewsController(await SharedPreferences.getInstance());
    news.sources[1] = NewsSource(1, 'ExampleNews', 'News');
    for (final modern in [true, false]) {
      news.record({
        'chat_id': 1, 'id': modern ? 2 : 1, 'date': 1700000000,
        'content': {
          '@type': 'messageText', 'text': {'text': 'فیلم خبر'},
          if (modern) 'link_preview': {'type': {
            '@type': 'linkPreviewTypeVideo',
            'video': {'video': {'id': 42}},
          }} else 'web_page': {'video': {'video': {'id': 42}}},
        },
      });
    }
    expect(news.feed.length, 2);
    for (final post in news.feed) {
      expect(post.body, 'فیلم خبر');
      expect(post.mediaKind, 'video');
      expect(post.mediaFileId, 42);
    }
    news.dispose();
  });

  test('unsupported cached post is replaced when native engine resolves its video', () async {
    SharedPreferences.setMockInitialValues({});
    final news = TdNewsController(await SharedPreferences.getInstance());
    news.sources[1] = NewsSource(1, 'ExampleNews', 'News');
    news.record({'chat_id': 1, 'id': 1, 'date': 1700000000,
      'content': {'@type': 'messageUnsupported'}});
    expect(news.feed.single.mediaKind, 'unsupported');
    expect(news.feed.single.body, isNot(contains('تلگرام باز کنید')));
    news.onEvent({'@type': 'updateMessageContent', 'chat_id': 1, 'message_id': 1,
      'new_content': {'@type': 'messageVideo', 'video': {'video': {'id': 43}},
        'caption': {'text': 'فیلم بازیابی‌شده'}}});
    expect(news.feed.single.mediaKind, 'video');
    expect(news.feed.single.mediaFileId, 43);
    expect(news.feed.single.body, 'فیلم بازیابی‌شده');
    news.dispose();
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
