import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'td_news_engine.dart';
import 'td_media_viewer.dart';
import 'td_downloads.dart';

/// Chat with the signed-in account's actual Telegram Saved Messages.
class TelegramSavedMessagesPage extends StatefulWidget {
  final TdNewsController news;
  final bool embedded;
  const TelegramSavedMessagesPage({
    super.key, required this.news, this.embedded = false,
  });
  @override
  State<TelegramSavedMessagesPage> createState() =>
      _TelegramSavedMessagesPageState();
}

class _TelegramSavedMessagesPageState extends State<TelegramSavedMessagesPage> {
  final composer = TextEditingController();
  final saving = <String>{};
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.news.state == 'authorizationStateReady' &&
        widget.news.bridge.sender != null) {
      unawaited(widget.news.loadTelegramSavedMessages());
    }
  }

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  void notice(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty) return;
    final message = composer.text;
    setState(() { sending = true; });
    try {
      await widget.news.sendTelegramSavedText(message);
      if (mounted) {
        composer.clear();
        notice('پیام برای ارسال به تلگرام ثبت شد.');
      }
    } catch (_) {
      notice('ارسال پیام انجام نشد؛ اتصال تلگرام را بررسی کنید.');
    } finally {
      if (mounted) setState(() { sending = false; });
    }
  }

  Future<void> download(NewsPost post) async {
    if (!saving.add(post.key)) return;
    setState(() {});
    try {
      await NewsDownloadService.save(widget.news, post);
      notice('فایل در دانلودهای گوشی ذخیره شد.');
    } catch (_) {
      notice('دانلود فایل انجام نشد.');
    } finally {
      saving.remove(post.key);
      if (mounted) setState(() {});
    }
  }

  Widget bubble(NewsPost post) {
    final colors = Theme.of(context).colorScheme;
    final hasFile = post.mediaFileId != null || post.photoId != null;
    final viewable = post.mediaKind == 'photo' ||
        post.mediaKind == 'video' || post.mediaKind == 'pdf';
    if (post.photoId != null && post.photoPath == null) {
      widget.news.requestThumbnail(post);
    }
    final preview = post.photoPath != null && post.photoPath!.isNotEmpty
        ? Image.file(File(post.photoPath!), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
        : post.previewBytes != null
            ? Image.memory(post.previewBytes!, fit: BoxFit.cover)
            : null;
    final date = DateTime.fromMillisecondsSinceEpoch(post.date * 1000).toLocal();
    final time = date.hour.toString().padLeft(2, '0') + ':' +
        date.minute.toString().padLeft(2, '0');
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .65),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(19), topRight: Radius.circular(19),
              bottomLeft: Radius.circular(19), bottomRight: Radius.circular(5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (preview != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 170, child: preview)),
              const SizedBox(height: 8),
            ],
            if (post.body.trim().isNotEmpty)
              SelectableText(post.body, textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 15, height: 1.65,
                  color: colors.onPrimaryContainer)),
            if (post.fileName?.isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(post.fileName!, style: TextStyle(
                fontSize: 12, color: colors.onPrimaryContainer)),
            ],
            if (hasFile)
              Wrap(spacing: 6, runSpacing: 2, children: [
                if (viewable)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) =>
                          NewsMediaViewer(news: widget.news, post: post))),
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('نمایش فایل')),
                TextButton.icon(
                  onPressed: saving.contains(post.key) ? null : () => download(post),
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('دانلود')),
              ]),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft,
              child: Text(time, textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 10,
                  color: colors.onPrimaryContainer.withValues(alpha: .65)))),
          ]),
        ),
      ),
    );
  }

  Widget chat() {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .4)))),
        child: Row(children: [
          CircleAvatar(backgroundColor: colors.primaryContainer,
            child: Icon(Icons.bookmark_rounded, color: colors.primary)),
          const SizedBox(width: 11),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('پیام‌های ذخیره‌شده',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('گفت‌وگوی شخصی حساب تلگرام شما',
                style: TextStyle(fontSize: 11)),
            ],
          )),
          IconButton(
            tooltip: 'تازه‌سازی پیام‌ها',
            onPressed: () => widget.news.loadTelegramSavedMessages(),
            icon: const Icon(Icons.refresh_rounded)),
        ]),
      ),
      Expanded(child: AnimatedBuilder(
        animation: widget.news,
        builder: (context, _) {
          final messages = widget.news.telegramSavedFeed;
          return RefreshIndicator(
            onRefresh: () => widget.news.loadTelegramSavedMessages(),
            child: ListView.builder(
              key: const ValueKey('telegram-saved-chat'),
              reverse: true,
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: messages.length + 1,
              itemBuilder: (context, index) {
                if (index < messages.length) return bubble(messages[index]);
                if (widget.news.telegramSavedError != null) {
                  return Padding(padding: const EdgeInsets.all(18),
                    child: TextButton(
                      onPressed: () => widget.news.loadTelegramSavedMessages(),
                      child: Text(widget.news.telegramSavedError! + '\nتلاش دوباره')));
                }
                if (messages.isEmpty && widget.news.telegramSavedBusy) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(25),
                    child: CircularProgressIndicator()));
                }
                if (messages.isEmpty) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('اینجا می‌توانید یادداشت‌ها و خبرها را برای خودتان بفرستید.',
                      textAlign: TextAlign.center)));
                }
                if (widget.news.telegramSavedBusy) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator()));
                }
                if (!widget.news.telegramSavedHasMore) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: () =>
                      widget.news.loadTelegramSavedMessages(older: true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('پیام‌های قدیمی‌تر'));
              },
            ),
          );
        },
      )),
      SafeArea(top: false, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .5)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            key: const ValueKey('saved-chat-composer'),
            controller: composer,
            minLines: 1, maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'پیامی برای خودتان بنویسید…',
              filled: true,
              fillColor: colors.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 9),
          IconButton.filled(
            key: const ValueKey('saved-chat-send'),
            tooltip: 'ارسال پیام به Saved Messages',
            onPressed: sending ? null : send,
            icon: sending
                ? const SizedBox(width: 17, height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded)),
        ]),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? chat()
      : Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('پیام‌های ذخیره‌شده')),
            body: chat(),
          ));
}
