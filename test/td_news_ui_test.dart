import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';
import 'package:telegram_news/td_news_main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel editor stays in settings, not on the news feed', (tester) async {
    SharedPreferences.setMockInitialValues({'td_ws_auto': false});
    final preferences = await SharedPreferences.getInstance();
    final news = TdNewsController(preferences);
    news.state = 'authorizationStateReady';

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: TdHome(
          news: news,
          onToggleTheme: () {},
          dark: false,
        ),
      ),
    ));
    expect(find.text('نبض خبر'), findsOneWidget);
    expect(find.text('اخبار سریع، مطمئن، به‌روز'), findsOneWidget);
    expect(find.text('افزودن کانال عمومی'), findsNothing);
    expect(find.text('هنوز منبع خبری ندارید'), findsOneWidget);

    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();
    expect(find.text('افزودن کانال عمومی'), findsOneWidget);
    expect(find.text('کانال‌های من'), findsOneWidget);
    expect(find.textContaining('WebSocket'), findsNothing);
    await tester.scrollUntilVisible(find.text('حالت تاریک'), 220,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('حالت تاریک'), findsOneWidget);
    expect(find.byKey(const ValueKey('mtproto-connect')), findsNothing);
    expect(find.byKey(const ValueKey('telegram-saved-messages')), findsNothing);
    expect(find.byKey(const ValueKey('mtproto-proxy-link')), findsNothing);

    await tester.tap(find.text('خبرها'));
    await tester.pumpAndSettle();
    expect(find.text('نبض خبر'), findsOneWidget);
    expect(find.text('افزودن کانال عمومی'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });
  testWidgets('news star sends to Telegram and Saved Messages tab is a chat',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"Example News"}',
      ],
    });
    final news = TdNewsController(await SharedPreferences.getInstance());
    news.state = 'authorizationStateReady';
    news.record({
      'chat_id': -100123456,
      'id': 125 * 1048576,
      'date': 1700000010,
      'content': {
        '@type': 'messageText', 'text': {'text': 'خبر قابل ذخیره'},
      },
    });
    final post = news.feed.single;
    await tester.pumpWidget(MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: TdHome(news: news, onToggleTheme: () {}, dark: false),
    )));
    expect(find.byKey(ValueKey('bookmark-' + post.key)), findsOneWidget);
    expect(find.text('ذخیره در تلگرام'), findsOneWidget);
    expect(news.isForwardedToTelegram(post), isFalse);

    await tester.tap(find.text('پیام‌های من').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('telegram-saved-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-chat-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-chat-send')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('saved-chat-composer')), 'یادداشت آزمایشی');
    expect(find.text('یادداشت آزمایشی'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });

  testWidgets('photo news has download and a full-page continuation', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"Example News"}',
      ],
    });
    final preferences = await SharedPreferences.getInstance();
    final news = TdNewsController(preferences);
    news.state = 'authorizationStateReady';
    final fullCaption = 'عنوان خبر\\n' +
        List.filled(14, 'متن طولانی خبر برای خواندن کامل.').join(' ') +
        '\\nپایان خبر بدون حذف یا کوتاه‌سازی.';
    news.record({
      'chat_id': -100123456,
      'id': 126 * 1048576,
      'date': 1700000010,
      'content': {
        '@type': 'messagePhoto',
        'caption': {'text': fullCaption},
        'photo': {'sizes': [
          {'width': 640, 'height': 400, 'photo': {'id': 701}},
        ]},
      },
    });
    final post = news.feed.single;

    await tester.pumpWidget(MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: TdHome(news: news, onToggleTheme: () {}, dark: false),
    )));
    expect(find.byKey(ValueKey('bookmark-' + post.key)), findsOneWidget);
    expect(find.byKey(ValueKey('download-' + post.key)), findsOneWidget);
    final more = find.byKey(ValueKey('read-more-' + post.key));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('متن کامل خبر'), findsOneWidget);
    final fullText = tester.widget<SelectableText>(
        find.byKey(ValueKey('article-full-text-' + post.key)));
    expect(fullText.data, fullCaption);
    // The full caption is deliberately long: the attachment action starts
    // below the viewport in the lazy, scrollable article page.
    await tester.scrollUntilVisible(find.text('مشاهده عکس با اندازه کامل'),
        220, scrollable: find.byType(Scrollable).last);
    expect(find.text('مشاهده عکس با اندازه کامل'), findsOneWidget);
    expect(find.text('ذخیره این خبر'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('download-' + post.key)), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });
}
