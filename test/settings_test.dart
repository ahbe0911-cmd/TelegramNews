import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/models.dart';

void main() {
  test('overnight quiet hours and boundaries', () {
    expect(quietNow(DateTime(2026, 1, 1, 23), true, 1320, 480), true);
    expect(quietNow(DateTime(2026, 1, 1, 7, 59), true, 1320, 480), true);
    expect(quietNow(DateTime(2026, 1, 1, 8), true, 1320, 480), false);
    expect(quietNow(DateTime(2026, 1, 1, 12), true, 1320, 480), false);
    expect(quietNow(DateTime(2026, 1, 1, 22), false, 1320, 480), false);
  });
  test('same-day and full-day quiet hours', () {
    expect(quietNow(DateTime(2026, 1, 1, 12), true, 600, 800), true);
    expect(quietNow(DateTime(2026, 1, 1, 12), true, 0, 0), true);
  });
  test('Persian digits and Nowruz conversion', () {
    expect(fa('10:59'), '۱۰:۵۹');
    expect(persianDate(DateTime(2024, 3, 20)), contains('۱۴۰۳'));
  });
}
