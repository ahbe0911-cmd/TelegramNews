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
    expect(find.text('آخرین خبرها'), findsOneWidget);
    expect(find.text('آخرین اخبار کانال‌های شما'), findsOneWidget);
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

    await tester.tap(find.text('خبرها'));
    await tester.pumpAndSettle();
    expect(find.text('آخرین خبرها'), findsOneWidget);
    expect(find.text('افزودن کانال عمومی'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });
  testWidgets('star saves a news card and saved tab shows and removes it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"Example News"}',
      ],
    });
    final preferences = await SharedPreferences.getInstance();
    final news = TdNewsController(preferences);
    news.state = 'authorizationStateReady';
    news.record({
      'chat_id': -100123456,
      'id': 125 * 1048576,
      'date': 1700000010,
      'content': {
        '@type': 'messageText',
        'text': {'text': 'خبر قابل ذخیره'},
      },
    });
    final post = news.feed.single;

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: TdHome(news: news, onToggleTheme: () {}, dark: false),
      ),
    ));

    expect(find.byKey(ValueKey('bookmark-' + post.key)), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('bookmark-' + post.key)));
    await tester.pump();
    expect(news.isSaved(post), isTrue);

    await tester.tap(find.text('ذخیره‌شده‌ها').last);
    await tester.pump();
    expect(find.text('خبر قابل ذخیره'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('bookmark-' + post.key)));
    await tester.pump();
    expect(news.savedFeed, isEmpty);
    expect(find.text('هنوز خبری ذخیره نشده است'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });

}
