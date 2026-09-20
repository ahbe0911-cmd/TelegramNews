import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import 'td_news_engine.dart';

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
  String? error;
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
      if (widget.post.mediaKind == 'pdf') {
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
    return Scaffold(
      appBar: AppBar(title: Text(isPdf ? 'نمایش سند PDF' : 'پخش ویدئو')),
      body: SafeArea(
        child: loading
            ? const Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 17),
                  Text('در حال دریافت فایل از تلگرام…'),
                ],
              ))
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center),
                  ))
                : isPdf
                    ? PdfViewPinch(controller: pdf!)
                    : Center(child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _videoPlayer(),
                      )),
      ),
    );
  }
}
