import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gozar_shortcuts.dart';
import 'gozar_visuals.dart';
import 'td_system_vpn.dart';

/// Independent of the ten home shortcuts: launcher sections have their own
/// saved app lists, layout and stable Android launcher Activity identifiers.
class GozarLauncherSection {
  final String id;
  final String title;
  final int columns;
  final double iconSize;
  final List<GozarShortcut> apps;

  const GozarLauncherSection({
    required this.id, required this.title,
    this.columns = 5, this.iconSize = 60, this.apps = const [],
  });

  GozarLauncherSection copyWith({
    String? title, int? columns, double? iconSize, List<GozarShortcut>? apps,
  }) => GozarLauncherSection(
    id: id, title: title ?? this.title, columns: columns ?? this.columns,
    iconSize: iconSize ?? this.iconSize, apps: apps ?? this.apps);

  Map<String, Object> toJson() => {
    'id': id, 'title': title, 'columns': columns, 'iconSize': iconSize,
    'apps': apps.map((a) => a.toJson()).toList(),
  };

  static GozarLauncherSection? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final title = value['title']?.toString().trim() ?? '';
    final columns = value['columns'];
    final size = value['iconSize'];
    final rawApps = value['apps'];
    if (id.isEmpty || id.length > 100 ||
        title.isEmpty || title.length > 40 ||
        columns is! int || columns < 3 || columns > 6 ||
        size is! num || size < 36 || size > 72 ||
        rawApps is! List) return null;
    final apps = <GozarShortcut>[];
    final keys = <String>{};
    for (final item in rawApps) {
      final app = GozarShortcut.fromJson(item);
      if (app != null && app.kind == 'app' && keys.add(app.key)) {
        apps.add(app);
        if (apps.length >= GozarLauncherStore.maxAppsPerSection) break;
      }
    }
    return GozarLauncherSection(
      id: id, title: title, columns: columns,
      iconSize: size.toDouble(), apps: apps);
  }
}

class GozarLauncherStore {
  static const key = 'gozar_launcher_sections_v1';
  static const maxSections = 8;
  static const maxAppsPerSection = 80;

  /// Drop an icon directly onto another icon to move it into that position.
  static List<GozarShortcut> moveApp(
      List<GozarShortcut> items, String sourceKey, String targetKey) {
    final original = List<GozarShortcut>.from(items);
    final from = original.indexWhere((app) => app.key == sourceKey);
    final to = original.indexWhere((app) => app.key == targetKey);
    if (from < 0 || to < 0 || from == to) return original;
    final moved = original.removeAt(from);
    original.insert(to, moved);
    return original;
  }

  static List<GozarLauncherSection> load(SharedPreferences preferences) {
    final raw = preferences.getString(key);
    if (raw == null) {
      return [const GozarLauncherSection(
        id: 'initial', title: 'برنامه‌های من')];
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return [];
      final result = <GozarLauncherSection>[];
      final ids = <String>{};
      for (final entry in parsed) {
        final section = GozarLauncherSection.fromJson(entry);
        if (section != null && ids.add(section.id)) {
          result.add(section);
          if (result.length == maxSections) break;
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> save(SharedPreferences preferences,
      List<GozarLauncherSection> sections) async {
    if (sections.length > maxSections ||
        sections.map((s) => s.id).toSet().length != sections.length ||
        sections.any((s) => s.title.trim().isEmpty ||
          s.title.length > 40 ||
          s.columns < 3 || s.columns > 6 ||
          s.iconSize < 36 || s.iconSize > 72 ||
          s.apps.length > maxAppsPerSection ||
          s.apps.any((a) => a.kind != 'app' ||
            GozarShortcut.fromJson(a.toJson()) == null) ||
          s.apps.map((a) => a.key).toSet().length != s.apps.length)) {
      return false;
    }
    return preferences.setString(key,
      jsonEncode(sections.map((s) => s.toJson()).toList()));
  }
}

/// Opens Android apps with the existing, verified native shortcut bridge.
class GozarLauncher extends StatefulWidget {
  final SharedPreferences preferences;
  final Future<void> Function(GozarShortcut shortcut) onOpenApp;
  const GozarLauncher({
    super.key, required this.preferences, required this.onOpenApp,
  });
  @override
  State<GozarLauncher> createState() => _GozarLauncherState();
}

class _GozarLauncherState extends State<GozarLauncher> {
  late List<GozarLauncherSection> sections;
  final PageController pages = PageController();
  int active = 0;
  int serial = 0;
  Future<void> pendingSave = Future<void>.value();
  bool showSettings = false;
  String draftSectionTitle = '';
  double? previewIconSize;
  List<Map<String, String>>? cachedInstalledApps;
  DateTime? installedAppsFetchedAt;

  @override
  void initState() {
    super.initState();
    sections = GozarLauncherStore.load(widget.preferences);
    if (sections.isNotEmpty) draftSectionTitle = sections.first.title;
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)));
    }
  }

  Future<void> persist(List<GozarLauncherSection> updated,
      {int? openIndex}) async {
    final original = sections;
    final oldPage = active;
    final destination = updated.isEmpty ? 0 :
        (openIndex ?? active).clamp(0, updated.length - 1);
    // Render the new icon order immediately. Queue disk writes rather than
    // dropping rapid rename/drag/column changes while a save is in flight.
    setState(() {
      sections = updated;
      active = destination;
      draftSectionTitle = updated.isEmpty ? '' : updated[destination].title;
      previewIconSize = null;
    });
    final write = pendingSave.then((_) async {
      bool saved;
      try {
        saved = await GozarLauncherStore.save(
            widget.preferences, updated);
      } catch (_) {
        saved = false;
      }
      if (!saved && mounted && identical(sections, updated)) {
        setState(() {
          sections = original;
          active = oldPage;
          draftSectionTitle =
              original.isEmpty ? '' : original[oldPage].title;
        });
        notice('تنظیمات لانچر ذخیره نشد.');
      }
    });
    pendingSave = write;
    await write;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pages.hasClients && sections.isNotEmpty &&
          active == destination) {
        pages.jumpToPage(active);
      }
    });
  }

  Future<void> configure({GozarLauncherSection? section}) async {
    final creating = section == null;
    if (creating && sections.length >= GozarLauncherStore.maxSections) {
      notice('حداکثر ۸ بخش می‌توان ساخت.');
      return;
    }
    final name = TextEditingController(text: section?.title ?? '');
    var columns = section?.columns ?? 5;
    var iconSize = section?.iconSize ?? 60.0;
    var deleting = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          key: const ValueKey('gozar-launcher-section-dialog'),
          scrollable: true,
          title: Text(creating ? 'افزودن بخش جدید' : 'تنظیمات بخش'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('gozar-launcher-section-name'),
                controller: name, maxLength: 40, autofocus: creating,
                decoration: const InputDecoration(
                  labelText: 'نام این بخش', hintText: 'مثلاً ساخت ویدئو'),
              ),
              const SizedBox(height: 10),
              const Text('چیدمان و ظاهر',
                style: TextStyle(color: GozarPalette.purple,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('تعداد ستون‌ها'),
              Wrap(spacing: 8, children: [
                for (final value in [3, 4, 5, 6])
                  ChoiceChip(
                    key: ValueKey('gozar-launcher-columns-' +
                        value.toString()),
                    label: Text(value.toString()),
                    selected: columns == value,
                    onSelected: (_) => update(() { columns = value; }),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('اندازه آیکن')),
                Text(iconSize.round().toString() + 'dp',
                  style: const TextStyle(color: GozarPalette.cyan)),
              ]),
              Slider(
                key: const ValueKey('gozar-launcher-icon-size'),
                min: 36, max: 72, divisions: 12, value: iconSize,
                onChanged: (value) => update(() { iconSize = value; }),
              ),
              if (!creating) TextButton.icon(
                key: const ValueKey('gozar-launcher-delete-section'),
                onPressed: () {
                  deleting = true;
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.delete_outline,
                  color: GozarPalette.red),
                label: const Text('حذف این بخش',
                  style: TextStyle(color: GozarPalette.red)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
            FilledButton(
              key: const ValueKey('gozar-launcher-save-section'),
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('نام بخش را وارد کنید.')));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    final title = name.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    if (!mounted || accepted != true) return;
    if (deleting && section != null) {
      final remaining = sections.where((s) => s.id != section.id).toList();
      await persist(remaining, openIndex: active.clamp(0,
        remaining.isEmpty ? 0 : remaining.length - 1));
    } else if (title.isNotEmpty && title.length <= 40) {
      if (creating) {
        final next = GozarLauncherSection(
          id: DateTime.now().microsecondsSinceEpoch.toString() +
              '-' + (serial++).toString(),
          title: title, columns: columns, iconSize: iconSize,
        );
        await persist([...sections, next], openIndex: sections.length);
      } else {
        final index = sections.indexWhere((s) => s.id == section.id);
        if (index < 0) return;
        final updated = [...sections];
        updated[index] = updated[index].copyWith(
          title: title, columns: columns, iconSize: iconSize);
        await persist(updated, openIndex: index);
      }
    }
  }

  Future<void> updateSection(GozarLauncherSection section, {
    String? title, int? columns, double? iconSize,
  }) async {
    final index = sections.indexWhere((s) => s.id == section.id);
    if (index < 0) return;
    final next = [...sections];
    next[index] = next[index].copyWith(
      title: title, columns: columns, iconSize: iconSize,
    );
    await persist(next, openIndex: index);
  }

  Future<void> renameApp(GozarLauncherSection section,
      GozarShortcut app) async {
    // Let Flutter own the form field's internal controller for the entire
    // route exit animation. Disposing an external controller right after
    // Navigator.pop() caused a real widget-test crash on fast navigation.
    var draft = app.title;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('gozar-launcher-rename-dialog'),
        title: const Text('ویرایش نام برنامه در لانچر'),
        content: TextFormField(
          key: const ValueKey('gozar-launcher-app-name'),
          initialValue: app.title,
          autofocus: true, maxLength: 48,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'نام نمایشی',
            helperText: 'نام اصلی برنامه و مسیر اجرای آن تغییر نمی‌کند.',
          ),
          onChanged: (text) { draft = text; },
          onFieldSubmitted: (text) {
            if (text.trim().isNotEmpty) {
              Navigator.pop(dialogContext, text.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف')),
          FilledButton(
            key: const ValueKey('gozar-launcher-save-app-name'),
            onPressed: () {
              final name = draft.trim();
              if (name.isEmpty || name.length > 48) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text(
                    'نام برنامه باید بین ۱ تا ۴۸ نویسه باشد.')));
                return;
              }
              Navigator.pop(dialogContext, name);
            },
            child: const Text('ذخیره نام'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value == app.title) return;
    final sectionIndex = sections.indexWhere((s) => s.id == section.id);
    if (sectionIndex < 0) return;
    final current = sections[sectionIndex];
    final appIndex = current.apps.indexWhere((s) => s.key == app.key);
    if (appIndex < 0) return;
    final updatedApps = [...current.apps];
    updatedApps[appIndex] = updatedApps[appIndex].renamed(value);
    final updated = [...sections];
    updated[sectionIndex] = current.copyWith(apps: updatedApps);
    await persist(updated, openIndex: sectionIndex);
  }

  Future<void> reorderApp(GozarLauncherSection section,
      String sourceKey, String targetKey) async {
    final index = sections.indexWhere((s) => s.id == section.id);
    if (index < 0) return;
    final current = sections[index];
    final reordered = GozarLauncherStore.moveApp(
        current.apps, sourceKey, targetKey);
    if (reordered.map((s) => s.key).join('|') ==
        current.apps.map((s) => s.key).join('|')) return;
    final next = [...sections];
    next[index] = current.copyWith(apps: reordered);
    await persist(next, openIndex: index);
  }

  Future<void> moveAppByStep(GozarLauncherSection section,
      GozarShortcut app, int delta) async {
    final index = section.apps.indexWhere((s) => s.key == app.key);
    final destination = index + delta;
    if (index < 0 || destination < 0 ||
        destination >= section.apps.length) return;
    await reorderApp(section, app.key, section.apps[destination].key);
  }

  Widget inlineSectionSettings(GozarLauncherSection section) {
    return Container(
      key: const ValueKey('gozar-launcher-inline-settings'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xff102642),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GozarPalette.blue.withOpacity(.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.tune_rounded, color: GozarPalette.cyan, size: 19),
          const SizedBox(width: 6),
          const Expanded(child: Text('تنظیمات همین بخش',
            style: TextStyle(color: GozarPalette.text,
              fontWeight: FontWeight.bold))),
          IconButton(
            key: const ValueKey('gozar-launcher-close-settings'),
            tooltip: 'بستن تنظیمات لانچر',
            onPressed: () => setState(() { showSettings = false; }),
            icon: const Icon(Icons.close_rounded, size: 19)),
        ]),
        TextFormField(
          key: ValueKey('gozar-launcher-inline-name-' + section.id),
          initialValue: draftSectionTitle,
          maxLength: 40,
          onChanged: (value) { draftSectionTitle = value; },
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              updateSection(section, title: value.trim());
            }
          },
          decoration: InputDecoration(
            labelText: 'نام بخش',
            suffixIcon: IconButton(
              key: const ValueKey('gozar-launcher-save-inline-name'),
              tooltip: 'ذخیره نام بخش',
              icon: const Icon(Icons.check_circle_outline_rounded,
                color: GozarPalette.cyan),
              onPressed: () {
                final name = draftSectionTitle.trim();
                if (name.isEmpty || name.length > 40) {
                  notice('نام بخش باید بین ۱ تا ۴۰ نویسه باشد.');
                  return;
                }
                updateSection(section, title: name);
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('تعداد ستون‌ها',
            style: TextStyle(color: GozarPalette.text, fontSize: 12))),
          for (final columns in [3, 4, 5, 6])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                key: ValueKey('gozar-launcher-inline-cols-' +
                    columns.toString()),
                label: Text(columns.toString()),
                selected: section.columns == columns,
                onSelected: (_) =>
                    updateSection(section, columns: columns),
              ),
            ),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          const Expanded(child: Text('اندازه آیکن',
            style: TextStyle(color: GozarPalette.text, fontSize: 12))),
          Text((previewIconSize ?? section.iconSize).round().toString() +
              'dp', style: const TextStyle(color: GozarPalette.cyan)),
        ]),
        Slider(
          key: const ValueKey('gozar-launcher-inline-icon-size'),
          value: previewIconSize ?? section.iconSize,
          min: 36, max: 72, divisions: 12,
          onChanged: (value) =>
            setState(() { previewIconSize = value; }),
          onChangeEnd: (value) =>
            updateSection(section, iconSize: value),
        ),
        const Divider(height: 15),
        OutlinedButton.icon(
          key: const ValueKey('gozar-launcher-inline-delete-section'),
          onPressed: () => confirmDeleteSection(section),
          icon: const Icon(Icons.delete_outline_rounded,
            color: GozarPalette.red),
          label: const Text('حذف این بخش',
            style: TextStyle(color: GozarPalette.red)),
        ),
      ]),
    );
  }

  Future<void> confirmDeleteSection(GozarLauncherSection section) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف بخش لانچر'),
        content: Text('بخش «' + section.title +
          '» و میانبرهای داخل آن حذف شوند؟ '
          'خود برنامه‌های گوشی حذف نمی‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف بخش')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final remaining = sections.where((s) => s.id != section.id).toList();
    await persist(remaining, openIndex:
        active.clamp(0, remaining.isEmpty ? 0 : remaining.length - 1));
    if (mounted) setState(() { showSettings = false; });
  }

  Future<void> addApps(GozarLauncherSection section) async {
    List<Map<String, String>> installed;
    final cached = cachedInstalledApps;
    final fetched = installedAppsFetchedAt;
    if (cached != null && fetched != null &&
        DateTime.now().difference(fetched) < const Duration(seconds: 30)) {
      installed = cached;
    } else {
      try {
        installed = await SystemVpnBridge.installedApps();
        cachedInstalledApps = installed;
        installedAppsFetchedAt = DateTime.now();
      } catch (_) {
        notice('فهرست برنامه‌های نصب‌شده دریافت نشد.');
        return;
      }
    }
    if (!mounted) return;
    var filter = '';
    final selected = <String, GozarShortcut>{
      for (final app in section.apps) app.key: app,
    };
    final result = await showModalBottomSheet<List<GozarShortcut>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GozarPalette.navy,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final matching = installed.where((app) =>
            (app['label'] ?? '').toLowerCase().contains(filter) ||
            (app['package'] ?? '').toLowerCase().contains(filter)).toList();
          return SafeArea(child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .76,
              child: Column(children: [
                const Padding(padding: EdgeInsets.all(12),
                  child: Text('افزودن برنامه به بخش',
                    style: TextStyle(color: GozarPalette.text,
                      fontSize: 18, fontWeight: FontWeight.w800))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    key: const ValueKey('gozar-launcher-app-search'),
                    onChanged: (value) => update(() {
                      filter = value.trim().toLowerCase();
                    }),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'جستجوی برنامه‌های نصب‌شده',
                    ),
                  )),
                const SizedBox(height: 8),
                Expanded(child: matching.isEmpty
                  ? const Center(child: Text('برنامه‌ای پیدا نشد.'))
                  : ListView.builder(
                      itemCount: matching.length,
                      itemBuilder: (context, index) {
                        final item = matching[index];
                        final app = GozarShortcut(
                          kind: 'app', target: item['package'] ?? '',
                          title: item['label'] ?? '',
                          component: item['component'] ?? '',
                        );
                        return CheckboxListTile(
                          key: ValueKey('gozar-launcher-pick-' + app.key),
                          secondary: GozarShortcutIcon(
                            shortcut: app, size: 36),
                          title: Text(app.title),
                          subtitle: Text(app.target, maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                          value: selected.containsKey(app.key),
                          onChanged: (checked) => update(() {
                            if (checked == true &&
                                selected.length <
                                  GozarLauncherStore.maxAppsPerSection) {
                              selected[app.key] = app;
                            } else if (checked == false) {
                              selected.remove(app.key);
                            }
                          }),
                        );
                      },
                    )),
                Padding(padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    key: const ValueKey('gozar-launcher-save-apps'),
                    onPressed: () => Navigator.pop(sheetContext,
                        selected.values.toList()),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('ذخیره ' + selected.length.toString() +
                        ' برنامه'),
                  )),
              ]),
            ),
          ));
        },
      ),
    );
    if (!mounted || result == null) return;
    final index = sections.indexWhere((s) => s.id == section.id);
    if (index < 0) return;
    final updated = [...sections];
    updated[index] = updated[index].copyWith(apps: result);
    await persist(updated, openIndex: index);
  }

  Future<void> removeApp(GozarLauncherSection section,
      GozarShortcut app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف از بخش'),
        content: Text('«' + app.title +
            '» از این بخش حذف شود؟ خود برنامه از گوشی حذف نمی‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف میانبر')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final index = sections.indexWhere((s) => s.id == section.id);
    if (index < 0) return;
    final updated = [...sections];
    updated[index] = updated[index].copyWith(
      apps: updated[index].apps.where((a) => a.key != app.key).toList());
    await persist(updated, openIndex: index);
  }

  Widget appTile(GozarLauncherSection section,
      GozarShortcut app, double cellWidth, {bool controls = true}) {
    final size = math.min(section.iconSize, cellWidth - 14)
        .clamp(28.0, 72.0);
    return InkWell(
      key: ValueKey('gozar-launcher-open-' + app.key),
      borderRadius: BorderRadius.circular(16),
      onTap: controls ? () => widget.onOpenApp(app) : null,
      child: Column(children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xff193654),
              border: Border.all(color: GozarPalette.blue.withOpacity(.25)),
            ),
            child: Center(child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GozarShortcutIcon(shortcut: app, size: size),
            )),
          )),
          if (controls) Positioned(top: 0, right: 0, child: SizedBox(
            width: 28, height: 30,
            child: PopupMenuButton<String>(
              key: ValueKey('gozar-launcher-app-menu-' + app.key),
              tooltip: 'ویرایش یا جابه‌جایی برنامه',
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.more_horiz_rounded,
                color: GozarPalette.cyan),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename',
                  child: Text('ویرایش نام')),
                PopupMenuItem(value: 'before',
                  child: Text('انتقال به قبل')),
                PopupMenuItem(value: 'after',
                  child: Text('انتقال به بعد')),
                PopupMenuItem(value: 'remove',
                  child: Text('حذف از این بخش')),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'rename':
                    renameApp(section, app);
                    return;
                  case 'before':
                    moveAppByStep(section, app, -1);
                    return;
                  case 'after':
                    moveAppByStep(section, app, 1);
                    return;
                  case 'remove':
                    removeApp(section, app);
                    return;
                }
              },
            ),
          )),
        ])),
        const SizedBox(height: 5),
        Text(app.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GozarPalette.text, fontSize: 10.5)),
      ]),
    );
  }

  /// Long-press any program and drop it on a different icon. The Android
  /// package/component remain untouched when the visual order changes.
  Widget draggableAppTile(GozarLauncherSection section,
      GozarShortcut app, double cellWidth) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != app.key &&
          section.apps.any((candidate) => candidate.key == details.data),
      onAcceptWithDetails: (details) =>
          reorderApp(section, details.data, app.key),
      builder: (context, accepted, rejected) => Container(
        decoration: accepted.isEmpty ? null : BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GozarPalette.cyan, width: 2),
        ),
        child: LongPressDraggable<String>(
          data: app.key,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: cellWidth,
              height: cellWidth / .76,
              child: Opacity(opacity: .88,
                child: appTile(section, app, cellWidth, controls: false)),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: .28,
            child: appTile(section, app, cellWidth),
          ),
          child: appTile(section, app, cellWidth),
        ),
      ),
    );
  }

  Widget sectionPage(GozarLauncherSection section) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = section.columns;
      final cellWidth = (constraints.maxWidth - 12 -
          (columns - 1) * 8) / columns;
      if (section.apps.isEmpty) {
        return Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.apps_rounded,
            color: GozarPalette.cyan, size: 44),
          const SizedBox(height: 10),
          const Text('این بخش هنوز برنامه‌ای ندارد.',
            style: TextStyle(color: GozarPalette.muted)),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('gozar-launcher-add-apps-empty'),
            onPressed: () => addApps(section),
            icon: const Icon(Icons.add_rounded),
            label: const Text('افزودن برنامه'),
          ),
        ]));
      }
      return GridView.builder(
        key: ValueKey('gozar-launcher-grid-' + section.id),
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
        itemCount: section.apps.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns, mainAxisSpacing: 14,
          crossAxisSpacing: 8, childAspectRatio: .76,
        ),
        itemBuilder: (context, index) =>
            draggableAppTile(section, section.apps[index], cellWidth),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final section = sections.isEmpty ? null :
        sections[active.clamp(0, sections.length - 1)];
    return Column(children: [
      // The launcher owns the very top of its content, rather than wasting
      // height on the VPN status toolbar from other tabs.
      Container(
        key: const ValueKey('gozar-launcher-top-toolbar'),
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: const LinearGradient(colors: [
            Color(0xff123f61), Color(0xff0a203d),
          ]),
          border: Border.all(color: GozarPalette.blue.withOpacity(.5)),
        ),
        child: Row(children: [
          const Icon(Icons.grid_view_rounded,
            color: GozarPalette.cyan, size: 23),
          const SizedBox(width: 7),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(section?.title ?? 'لانچر',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GozarPalette.text,
                  fontSize: 16, fontWeight: FontWeight.w800)),
              Text(section == null ? 'بخش جدید بسازید'
                : section.apps.length.toString() + ' برنامه · ' +
                  section.columns.toString() + ' ستون',
                style: const TextStyle(
                  color: GozarPalette.muted, fontSize: 10)),
            ],
          )),
          if (section != null) FilledButton.icon(
            key: const ValueKey('gozar-launcher-add-apps'),
            onPressed: () => addApps(section),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('افزودن', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: const Color(0xff1776a1),
            ),
          ),
          IconButton(
            key: const ValueKey('gozar-launcher-add-section'),
            tooltip: 'ساخت بخش جدید',
            onPressed: sections.length >= GozarLauncherStore.maxSections
                ? null : () => configure(),
            icon: const Icon(Icons.library_add_outlined,
              color: GozarPalette.cyan, size: 21)),
          IconButton(
            key: const ValueKey('gozar-launcher-section-settings'),
            tooltip: 'تنظیمات همین بخش',
            onPressed: section == null ? null
                : () => setState(() { showSettings = !showSettings; }),
            icon: Icon(showSettings
                ? Icons.tune_rounded : Icons.settings_outlined,
              color: showSettings
                ? GozarPalette.cyan : GozarPalette.muted, size: 21)),
        ]),
      ),
      if (sections.length > 1) SizedBox(
        height: 39,
        child: ListView.separated(
          key: const ValueKey('gozar-launcher-section-tabs'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: sections.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) => ChoiceChip(
            key: ValueKey('gozar-launcher-select-section-' +
                sections[index].id),
            label: Text(sections[index].title),
            selected: active == index,
            onSelected: (_) => pages.animateToPage(index,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic),
          ),
        ),
      ),
      if (showSettings && section != null) inlineSectionSettings(section),
      Expanded(child: sections.isEmpty
        ? Center(child: FilledButton.icon(
          key: const ValueKey('gozar-launcher-create-first'),
          onPressed: () => configure(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('ساخت اولین بخش'),
        ))
        : PageView.builder(
          key: const ValueKey('gozar-launcher-pages'),
          controller: pages,
          itemCount: sections.length,
          onPageChanged: (index) => setState(() {
            active = index;
            draftSectionTitle = sections[index].title;
            previewIconSize = null;
          }),
          itemBuilder: (context, index) => sectionPage(sections[index]),
        )),
      if (sections.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < sections.length; i++)
              GestureDetector(
                onTap: () => pages.animateToPage(i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == active ? 25 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: i == active ? GozarPalette.cyan :
                        GozarPalette.muted.withOpacity(.5)),
                ),
              ),
          ]),
        ),
    ]);
  }
}
