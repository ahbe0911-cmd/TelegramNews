import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';
import 'package:telegram_news/td_news_main.dart';
import 'package:telegram_news/td_inline_video.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('video plays in the feed only after an explicit tap and text is justified',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"خبرگزاری"}',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final news = TdNewsController(prefs);
    news.state = 'authorizationStateReady';
    news.record({
      'chat_id': -100123456,
      'id': 103 * 1048576,
      'date': 1700000001,
      'content': {
        '@type': 'messageVideo',
        'video': {'video': {'id': 4004}},
        'caption': {'text': 'متن آزمایشی ویدئو برای نمایش در فهرست'},
      },
    });
    await tester.pumpWidget(MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: TdHome(news: news, dark: false, onToggleTheme: () {}),
    )));
    expect(find.byType(NewsInlineVideo), findsNothing);
    final caption = tester.widget<Text>(
        find.text('متن آزمایشی ویدئو برای نمایش در فهرست'));
    expect(caption.textAlign, TextAlign.justify);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pump();
    expect(find.byType(NewsInlineVideo), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    news.dispose();
  });
}
