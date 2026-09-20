import 'package:flutter/services.dart';

import 'td_news_engine.dart';

/// Explicit save action: TDLib downloads on demand, then MediaStore writes to
/// Android's user-visible Downloads/NabzKhabar folder.
class NewsDownloadService {
  static const _channel = MethodChannel('ir.channel.telegram_tdnews/downloads');

  static String fileName(NewsPost post) {
    final original = post.fileName?.trim();
    if (original != null && original.isNotEmpty) return original;
    final extension = switch (post.mediaKind) {
      'photo' => 'jpg',
      'video' => 'mp4',
      'pdf' => 'pdf',
      _ => 'bin',
    };
    return 'NabzKhabar-' + (post.id >> 20).toString() + '.' + extension;
  }

  static String mimeType(NewsPost post) {
    final name = fileName(post).toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.mp4') || name.endsWith('.m4v')) return 'video/mp4';
    if (name.endsWith('.webm')) return 'video/webm';
    if (name.endsWith('.mp3')) return 'audio/mpeg';
    if (name.endsWith('.ogg')) return 'audio/ogg';
    if (name.endsWith('.apk')) return 'application/vnd.android.package-archive';
    if (name.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }

  static Future<String> save(TdNewsController news, NewsPost post) async {
    final localPath = await news.ensureMedia(post);
    final result = await _channel.invokeMethod<String>('save', {
      'path': localPath,
      'name': fileName(post),
      'mime': mimeType(post),
    });
    if (result == null || result.isEmpty) {
      throw StateError('ذخیره فایل کامل نشد.');
    }
    return result;
  }
}
