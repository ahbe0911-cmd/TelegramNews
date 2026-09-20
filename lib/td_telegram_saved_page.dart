import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'td_news_engine.dart';
import 'td_media_viewer.dart';
import 'td_downloads.dart';

/// The current Telegram account's personal Saved Messages, not app bookmarks.
class TelegramSavedMessagesPage extends StatefulWidget {
  final TdNewsController news;
  const TelegramSavedMessagesPage({super.key, required this.news});

  @override
  State<TelegramSavedMessagesPage> createState() => _TelegramSavedMessagesPageState();
}

class _TelegramSavedMessagesPageState extends State<TelegramSavedMessagesPage> {
  final saving = <String>{};

  @override
  void initState() {
    super.initState();
    // Load only on opening this page, not every time the news feed rebuilds.
    if (widget.news.bridge.sender != null &&
        widget.news.state == 'authorizationStateReady') {
      unawaited(widget.news.loadTelegramSavedMessages());
    }
  }

  Future<void> saveFile(NewsPost post) async {
    if (!saving.add(post.key)) return;
    setState(() {});
    try {
      await NewsDownloadService.save(widget.news, post);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل در پوشه دانلودها ذخیره شد.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دانلود فایل انجام نشد؛ اتصال را بررسی کنید.')));
    } finally {
      saving.remove(post.key);
      if (mounted) setState(() {});
    }
  }

  Widget savedCard(NewsPost post) {
    final colors = Theme.of(context).colorScheme;
    final kind = post.mediaKind;
    final hasFile = post.mediaFileId != null || post.photoId != null;
    final canOpen = kind == 'photo' || kind == 'video' || kind == 'pdf';
    final imagePath = post.photoPath;
    if (post.photoId != null && imagePath == null) {
      widget.news.requestThumbnail(post);
    }
    final preview = imagePath != null && imagePath.isNotEmpty
        ? Image.file(File(imagePath), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
        : post.previewBytes != null
            ? Image.memory(post.previewBytes!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
            : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(DateTime.fromMillisecondsSinceEpoch(post.date * 1000)
                  .toLocal().toString().substring(0, 16),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
            if (preview != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 170, child: preview)),
            ],
            if (post.body.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(post.body, textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 15, height: 1.65)),
            ],
            if (post.fileName != null && post.fileName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.fileName!, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            if (hasFile) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 7, children: [
                if (canOpen)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) =>
                          NewsMediaViewer(news: widget.news, post: post))),
                    icon: Icon(kind == 'video' ? Icons.play_circle_outline_rounded
                        : kind == 'pdf' ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined),
                    label: Text(kind == 'video' ? 'مشاهده ویدئو'
                        : kind == 'pdf' ? 'مشاهده PDF' : 'مشاهده عکس'),
                  ),
                OutlinedButton.icon(
                  onPressed: saving.contains(post.key) ? null : () => saveFile(post),
                  icon: saving.contains(post.key)
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: const Text('دانلود فایل'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('پیام‌های ذخیره‌شده تلگرام'),
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی پیام‌ها',
            onPressed: widget.news.telegramSavedBusy
                ? null : () => widget.news.loadTelegramSavedMessages(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.news,
        builder: (context, _) {
          final messages = widget.news.telegramSavedFeed;
          return RefreshIndicator(
            onRefresh: () => widget.news.loadTelegramSavedMessages(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text('پیام‌های ذخیره‌شده حساب تلگرام شما؛ مستقل از خبرهای نشان‌دار برنامه.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                if (widget.news.telegramSavedError != null) ...[
                  Text(widget.news.telegramSavedError!,
                    key: const ValueKey('telegram-saved-error')),
                  TextButton(
                    onPressed: () => widget.news.loadTelegramSavedMessages(),
                    child: const Text('تلاش دوباره')),
                ],
                if (messages.isEmpty && widget.news.telegramSavedBusy)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(25), child: CircularProgressIndicator())),
                if (messages.isEmpty && !widget.news.telegramSavedBusy &&
                    widget.news.telegramSavedError == null)
                  const Padding(
                    padding: EdgeInsets.all(25),
                    child: Text('هنوز پیامی در Saved Messages پیدا نشده است.')),
                for (final post in messages)
                  savedCard(post),
                if (messages.isNotEmpty && widget.news.telegramSavedHasMore)
                  FilledButton.icon(
                    onPressed: widget.news.telegramSavedBusy ? null
                        : () => widget.news.loadTelegramSavedMessages(older: true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('نمایش پیام‌های قدیمی‌تر'),
                  ),
                if (widget.news.telegramSavedBusy && messages.isNotEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(15), child: CircularProgressIndicator())),
              ],
            ),
          );
        },
      ),
    ),
  );
}
