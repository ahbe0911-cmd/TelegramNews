import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/td_news_engine.dart';
import 'package:telegram_news/td_downloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF, APK and photo attachments have separate full-size downloads', () async {
    SharedPreferences.setMockInitialValues({
      'td_channels': [
        '{"id":-100123456,"username":"ExampleNews","title":"خبرگزاری"}',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final news = TdNewsController(prefs);
    news.record({
      'chat_id': -100123456, 'id': 101 * 1048576, 'date': 1700000001,
      'content': {
        '@type': 'messagePhoto',
        'photo': {
          'sizes': [
            {'width': 640, 'height': 360, 'photo': {'id': 5101}},
            {'width': 1920, 'height': 1080, 'photo': {'id': 5102}},
          ],
        },
      },
    });
    final photo = news.feed.single;
    expect(photo.photoId, 5101);
    expect(photo.mediaFileId, 5102);
    expect(NewsDownloadService.fileName(photo), 'NabzKhabar-101.jpg');
    expect(NewsDownloadService.mimeType(photo), 'image/jpeg');

    news.record({
      'chat_id': -100123456, 'id': 102 * 1048576, 'date': 1700000002,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': 'application.apk',
          'document': {'id': 5110},
        },
      },
    });
    final apk = news.feed.first;
    expect(apk.mediaKind, 'file');
    expect(apk.mediaFileId, 5110);
    expect(NewsDownloadService.mimeType(apk), 'application/vnd.android.package-archive');

    news.record({
      'chat_id': -100123456, 'id': 103 * 1048576, 'date': 1700000003,
      'content': {
        '@type': 'messageDocument',
        'document': {
          'file_name': 'report.PDF',
          'document': {'id': 5130},
        },
      },
    });
    final pdf = news.feed.first;
    expect(pdf.mediaKind, 'pdf');
    expect(pdf.mediaFileId, 5130);
    expect(NewsDownloadService.mimeType(pdf), 'application/pdf');
    news.dispose();
  });
}
