import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gozar_visuals.dart';

/// Only user-chosen launchers are shown. No arbitrary apps are injected.
class GozarShortcut {
  final String kind; // "app" (Android package) or "web" (HTTPS URL).
  final String target;
  final String title;
  /// The selected Android launcher activity, blank for existing shortcuts.
  final String component;

  const GozarShortcut({
    required this.kind,
    required this.target,
    required this.title,
    this.component = '',
  });

  String get key => '$kind:$target:$component';

  /// Rename only the displayed label; never mutate the launcher component or URL.
  GozarShortcut renamed(String newTitle) => GozarShortcut(
    kind: kind, target: target, title: newTitle.trim(),
    component: component,
  );

  Map<String, String> toJson() =>
      {'kind': kind, 'target': target, 'title': title,
       'component': kind == 'app' ? component : ''};

  static GozarShortcut? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind']?.toString();
    final target = value['target']?.toString() ?? '';
    final title = value['title']?.toString() ?? '';
    final component = value['component']?.toString() ?? '';
    if (title.trim().isEmpty || title.length > 48 ||
        target.isEmpty || target.length > 2048) return null;
    if (kind == 'app' &&
        RegExp(r'^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$').hasMatch(target) &&
        (component.isEmpty || (component.length <= 256 &&
            RegExp(r'^[a-zA-Z0-9_.$]+$').hasMatch(component)))) {
      return GozarShortcut(kind: kind!, target: target,
          title: title, component: component);
    }
    if (kind == 'web' && validWebUrl(target) != null) {
      return GozarShortcut(kind: kind!, target: target, title: title);
    }
    return null;
  }

  static Uri? validWebUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.host.contains(' ') || uri.host.contains('..')) return null;
    return uri;
  }
}

class GozarShortcutStore {
  static const key = 'gozar_user_shortcuts_v1';
  static const maxCount = 10;

  /// Flutter's reorder callback supplies the insertion index *before* removal.
  static List<GozarShortcut> reordered(
      List<GozarShortcut> items, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= items.length ||
        newIndex < 0 || newIndex > items.length) {
      return List<GozarShortcut>.from(items);
    }
    final output = List<GozarShortcut>.from(items);
    final moved = output.removeAt(oldIndex);
    output.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
    return output;
  }

  static List<GozarShortcut> load(SharedPreferences preferences) {
    try {
      final raw = preferences.getString(key);
      if (raw == null) return [];
      final data = jsonDecode(raw);
      if (data is! List) return [];
      final output = <GozarShortcut>[];
      final unique = <String>{};
      for (final item in data) {
        final shortcut = GozarShortcut.fromJson(item);
        if (shortcut != null && unique.add(shortcut.key)) {
          output.add(shortcut);
          if (output.length == maxCount) break;
        }
      }
      return output;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> save(
      SharedPreferences preferences, List<GozarShortcut> items) async {
    if (items.length > maxCount ||
        items.any((item) => GozarShortcut.fromJson(item.toJson()) == null) ||
        items.map((item) => item.key).toSet().length != items.length) {
      return false;
    }
    return preferences.setString(key,
        jsonEncode(items.map((item) => item.toJson()).toList()));
  }
}

/// Android's real launcher artwork is fetched lazily, not guessed from a name.
class GozarShortcutIcon extends StatefulWidget {
  final GozarShortcut shortcut;
  final double size;
  const GozarShortcutIcon({
    super.key, required this.shortcut, this.size = 42,
  });

  @override
  State<GozarShortcutIcon> createState() => _GozarShortcutIconState();
}

class _GozarShortcutIconState extends State<GozarShortcutIcon> {
  static const _channel =
      MethodChannel('ir.channel.telegram_tdnews/system_vpn');
  static final Map<String, Future<Uint8List?>> _cache = {};
  late Future<Uint8List?> _icon;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant GozarShortcutIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shortcut.key != widget.shortcut.key) _resolve();
  }

  void _resolve() {
    if (widget.shortcut.kind == 'web') {
      _icon = Future<Uint8List?>.value(null);
      return;
    }
    // Small bounded cache: switching launcher sections never repeats native
    // icon requests, while a large installed-app picker cannot grow forever.
    if (!_cache.containsKey(widget.shortcut.key) && _cache.length >= 192) {
      _cache.remove(_cache.keys.first);
    }
    _icon = _cache.putIfAbsent(widget.shortcut.key, () async {
      try {
        return await _channel.invokeMethod<Uint8List>('appIcon', {
          'package': widget.shortcut.target,
          'component': widget.shortcut.component,
        });
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _icon,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data != null && data.isNotEmpty) {
        return Image.memory(data, width: widget.size, height: widget.size,
            fit: BoxFit.contain, gaplessPlayback: true);
      }
      return Icon(widget.shortcut.kind == 'web'
          ? Icons.public_rounded : Icons.apps_rounded,
          color: GozarPalette.cyan, size: widget.size * .78);
    },
  );
}
