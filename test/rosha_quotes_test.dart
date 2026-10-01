import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/rosha_quotes.dart';

void main() {
  test('Rosha ships a large diverse offline quote library', () {
    expect(roshaMotivationalQuotes.length, greaterThanOrEqualTo(100));
    expect(roshaMotivationalQuotes.toSet().length,
        roshaMotivationalQuotes.length);
    expect(
      roshaMotivationalQuotes.every(
        (quote) => quote.trim().length >= 20 && quote.trim().length <= 180,
      ),
      isTrue,
    );
  });
}
