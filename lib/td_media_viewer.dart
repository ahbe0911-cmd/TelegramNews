import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import 'td_news_engine.dart';
import 'td_downloads.dart';

class NewsMediaViewer extends StatefulWidget {
  final TdNewsController news;
  final NewsPost post;
  const NewsMediaViewer({super.key, required this.news, required this.post});

  @override
  State<NewsMediaViewer> createState() => _NewsMediaViewerState();
}

class _NewsMediaViewerState extends State<NewsMediaViewer> {
  VideoPlayerController? video;
  PdfControllerPinch? pdf;
  String? photoPath;
  String? error;
  bool saving = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _openMedia();
  }

  Future<void> _openMedia() async {
    try {
      final path = await widget.news.ensureMedia(widget.post);
      if (!mounted) return;
      if (widget.post.mediaKind == 'photo') {
        setState(() { photoPath = path; loading = false; });
      } else if (widget.post.mediaKind == 'pdf') {
        final controller = PdfControllerPinch(
          document: PdfDocument.openFile(path),
        );
        if (!mounted) {
          controller.dispose();
          return;
        }
        setState(() {
          pdf = controller;
          loading = false;
        });
      } else {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          video = controller;
          loading = false;
        });
        await controller.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'دریافت یا باز کردن فایل ممکن نشد؛ اتصال اینترنت را بررسی کنید یا خبر را در تلگرام باز کنید.';
        });
      }
    }
  }

  @override
  void dispose() {
    video?.dispose();
    pdf?.dispose();
    super.dispose();
  }

  Widget _videoPlayer() {
    final player = video!;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final duration = player.value.duration;
        final position = player.value.position;
        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble() : 1.0;
        final double value = position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AspectRatio(
            aspectRatio: player.value.aspectRatio > 0
                ? player.value.aspectRatio : 16 / 9,
            child: VideoPlayer(player),
          ),
          const SizedBox(height: 12),
          Row(children: [
            IconButton.filledTonal(
              tooltip: player.value.isPlaying ? 'مکث' : 'پخش',
              onPressed: () {
                if (player.value.isPlaying) {
                  player.pause();
                } else {
                  player.play();
                }
              },
              icon: Icon(player.value.isPlaying
                  ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            Expanded(child: Slider(
              value: value,
              max: max,
              onChanged: (next) =>
                  player.seekTo(Duration(milliseconds: next.round())),
            )),
            Text(_format(position) + ' / ' + _format(duration),
              style: const TextStyle(fontSize: 11)),
          ]),
        ]);
      },
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = widget.post.mediaKind == 'pdf';
    final isPhoto = widget.post.mediaKind == 'photo';
    return Scaffold(
      appBar: AppBar(
        title: Text(isPdf ? 'نمایش سند PDF'
            : isPhoto ? 'نمایش تصویر' : 'پخش ویدئو'),
        actions: [
          IconButton(
            tooltip: 'دانلود و ذخیره فایل',
            onPressed: saving ? null : () async {
              setState(() { saving = true; });
              try {
                await NewsDownloadService.save(widget.news, widget.post);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('در Downloads/NabzKhabar ذخیره شد.')));
              } catch (_) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ذخیره فایل انجام نشد.')));
              } finally {
                if (mounted) setState(() { saving = false; });
              }
            },
            icon: saving ? const SizedBox(width: 19, height: 19,
                child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? Center(child: AnimatedBuilder(
                animation: widget.news,
                builder: (context, _) {
                  final id = widget.post.mediaFileId ?? widget.post.photoId;
                  final progress = widget.news.downloadProgress[id];
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 52, height: 52,
                      child: CircularProgressIndicator(value: progress)),
                    const SizedBox(height: 15),
                    const Text('در حال دریافت فایل از تلگرام…'),
                    if (progress != null) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text((progress * 100).toStringAsFixed(0) + '٪'),
                    ),
                  ]);
                },
              ))
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 42),
                        const SizedBox(height: 12),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              loading = true;
                              error = null;
                            });
                            _openMedia();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('تلاش دوباره'),
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(widget.post.link),
                            mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('باز کردن خبر در تلگرام'),
                        ),
                      ],
                    ),
                  ))
                : isPdf
                    ? PdfViewPinch(controller: pdf!)
                    : isPhoto
                        ? InteractiveViewer(
                            minScale: 1, maxScale: 5,
                            child: Center(child: Image.file(File(photoPath!),
                              fit: BoxFit.contain)))
                    : Center(child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _videoPlayer(),
                      )),
      ),
    );
  }
}
