import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';
import 'package:telegram_news/td_news_main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel editor stays in settings, not on the news feed', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.text('افزودن کانال عمومی'), findsNothing);
    expect(find.text('هنوز منبع خبری ندارید'), findsOneWidget);

    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();
    expect(find.text('افزودن کانال عمومی'), findsOneWidget);
    expect(find.text('کانال‌های من'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('V2Ray ویژه اتصال تلگرام'), 170,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('V2Ray ویژه اتصال تلگرام'), findsOneWidget);
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
}
