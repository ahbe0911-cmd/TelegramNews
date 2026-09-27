import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_dual_main.dart';
import 'package:telegram_news/td_news_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dual controllers keep channels and bookmarks in separate namespaces',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final news = TdNewsController(
      prefs,
      storagePrefix: 'news',
      downloadFolder: 'NabzKhabar',
    );
    final cafenet = TdNewsController(
      prefs,
      storagePrefix: 'cafenet',
      downloadFolder: 'Cafenet',
    );

    news.sources[11] = NewsSource(11, 'NewsChannel', 'خبر');
    cafenet.sources[22] = NewsSource(22, 'CafeChannel', 'کافی‌نت');
    await news.persist();
    await cafenet.persist();

    final newsChannels = prefs.getStringList('news_td_channels') ?? const [];
    final cafeChannels = prefs.getStringList('cafenet_td_channels') ?? const [];
    expect(newsChannels.single, contains('NewsChannel'));
    expect(cafeChannels.single, contains('CafeChannel'));
    expect(newsChannels.single, isNot(contains('CafeChannel')));
    expect(cafeChannels.single, isNot(contains('NewsChannel')));
    expect(news.downloadFolder, 'NabzKhabar');
    expect(cafenet.downloadFolder, 'Cafenet');

    news.dispose();
    cafenet.dispose();
  });

  testWidgets('combined app exposes retained swipe pages with independent tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'dual_active_page': 0,
      'dual_news_dark': false,
      'dual_cafenet_dark': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(DualNewsApp(preferences: prefs));
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byKey(const ValueKey('dual-news-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('dual-cafenet-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('dual-active-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dual-tab-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dual-active-1')), findsOneWidget);
    expect(prefs.getInt('dual_active_page'), 1);
  });
}
