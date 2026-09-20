import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'td_news_engine.dart';

/// A player is instantiated only on tap. Other cards retain lightweight thumbnails.
class NewsInlineVideo extends StatefulWidget {
  final TdNewsController news;
  final NewsPost post;
  final VoidCallback onClose;
  const NewsInlineVideo({super.key, required this.news, required this.post, required this.onClose});
  @override
  State<NewsInlineVideo> createState() => _NewsInlineVideoState();
}

class _NewsInlineVideoState extends State<NewsInlineVideo> with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool loading = true;
  String? error;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final filePath = await widget.news.ensureMedia(widget.post);
      if (!mounted) return;
      final controller = VideoPlayerController.file(File(filePath));
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      setState(() { player = controller; loading = false; });
      await controller.play();
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'پخش ویدئو ممکن نشد. اتصال و قالب فایل را بررسی کنید.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.pause();
    player?.dispose();
    super.dispose();
  }

  String _time(Duration v) => v.inMinutes.toString().padLeft(2, '0') +
      ':' + v.inSeconds.remainder(60).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (loading) {
      final poster = widget.post.photoPath;
      final small = widget.post.previewBytes;
      return SizedBox(
        height: 208,
        child: Stack(fit: StackFit.expand, children: [
          if (poster != null)
            Image.file(File(poster), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xff152b42)))
          else if (small != null)
            Image.memory(small, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xff152b42)))
          else
            const ColoredBox(color: Color(0xff152b42)),
          const ColoredBox(color: Color(0x99000000)),
          Center(child: AnimatedBuilder(
            animation: widget.news,
            builder: (context, _) {
              final progress = widget.news.downloadProgress[widget.post.mediaFileId];
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 50, height: 50,
                  child: CircularProgressIndicator(
                    value: progress, strokeWidth: 3, color: Colors.white)),
                const SizedBox(height: 12),
                const Text('در حال آماده‌سازی ویدئو…',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                if (progress != null)
                  Text((progress * 100).toStringAsFixed(0) + '٪ دریافت شده',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('بستن پخش',
                    style: TextStyle(color: Colors.white)),
                ),
              ]);
            },
          )),
        ]),
      );
    }
    if (error != null) return SizedBox(height: 176, child: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(error!, textAlign: TextAlign.center),
        TextButton.icon(
          onPressed: () { setState(() { error = null; loading = true; }); _load(); },
          icon: const Icon(Icons.refresh_rounded), label: const Text('تلاش دوباره'),
        ),
        TextButton(onPressed: widget.onClose, child: const Text('بستن')),
      ],
    )));
    final controller = player!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final duration = controller.value.duration;
        final position = controller.value.position;
        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble() : 1.0;
        return ColoredBox(
          color: Colors.black,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio > 0
                  ? controller.value.aspectRatio : 16 / 9,
              child: VideoPlayer(controller),
            ),
            Row(children: [
              IconButton(
                color: Colors.white,
                tooltip: controller.value.isPlaying ? 'مکث' : 'پخش',
                icon: Icon(controller.value.isPlaying
                    ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: () => controller.value.isPlaying
                    ? controller.pause() : controller.play(),
              ),
              Expanded(child: Slider(
                min: 0, max: max,
                value: position.inMilliseconds.toDouble().clamp(0.0, max).toDouble(),
                onChanged: (next) => controller.seekTo(Duration(milliseconds: next.round())),
              )),
              Text(_time(position), style: const TextStyle(color: Colors.white, fontSize: 11)),
              IconButton(
                color: Colors.white,
                tooltip: muted ? 'فعال‌کردن صدا' : 'بی‌صدا',
                icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                onPressed: () {
                  setState(() { muted = !muted; });
                  controller.setVolume(muted ? 0 : 1);
                },
              ),
              IconButton(
                color: Colors.white, tooltip: 'بستن ویدئو',
                icon: const Icon(Icons.close_rounded), onPressed: widget.onClose,
              ),
            ]),
          ]),
        );
      },
    );
  }
}
