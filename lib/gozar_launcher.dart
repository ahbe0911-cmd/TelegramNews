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
  bool saving = false;
  bool showSettings = false;
  String draftSectionTitle = '';
  double? previewIconSize;

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
    if (saving) return;
    saving = true;
    final original = sections;
    final oldPage = active;
    final destination = updated.isEmpty ? 0 :
        (openIndex ?? active).clamp(0, updated.length - 1);
    setState(() {
      sections = updated;
      active = destination;
      draftSectionTitle = updated.isEmpty ? '' : updated[destination].title;
      previewIconSize = null;
    });
    final ok = await GozarLauncherStore.save(widget.preferences, updated);
    if (!ok && mounted) {
      setState(() {
        sections = original;
        active = oldPage;
        draftSectionTitle = original.isEmpty ? '' : original[oldPage].title;
      });
      notice('تنظیمات لانچر ذخیره نشد.');
    }
    saving = false;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pages.hasClients && sections.isNotEmpty) {
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

  Future<void> addApps(GozarLauncherSection section) async {
    List<Map<String, String>> installed;
    try {
      installed = await SystemVpnBridge.installedApps();
    } catch (_) {
      notice('فهرست برنامه‌های نصب‌شده دریافت نشد.');
      return;
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
      GozarShortcut app, double cellWidth) {
    final size = math.min(section.iconSize, cellWidth - 14)
        .clamp(28.0, 72.0);
    return InkWell(
      key: ValueKey('gozar-launcher-open-' + app.key),
      borderRadius: BorderRadius.circular(16),
      onTap: () => widget.onOpenApp(app),
      onLongPress: () => removeApp(section, app),
      child: Column(children: [
        Expanded(child: Container(
          width: double.infinity,
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
        const SizedBox(height: 5),
        Text(app.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GozarPalette.text, fontSize: 10.5)),
      ]),
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
            appTile(section, section.apps[index], cellWidth),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final section = sections.isEmpty ? null :
        sections[active.clamp(0, sections.length - 1)];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: Row(children: [
          const Icon(Icons.grid_view_rounded,
            color: GozarPalette.cyan, size: 24),
          const SizedBox(width: 7),
          Expanded(child: Text(section?.title ?? 'لانچر',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: GozarPalette.text,
              fontSize: 19, fontWeight: FontWeight.w800))),
          IconButton(
            key: const ValueKey('gozar-launcher-add-section'),
            tooltip: 'افزودن بخش جدید',
            onPressed: sections.length >= GozarLauncherStore.maxSections
                ? null : () => configure(),
            icon: const Icon(Icons.add_rounded,
              color: GozarPalette.cyan)),
          IconButton(
            key: const ValueKey('gozar-launcher-section-settings'),
            tooltip: 'تنظیمات بخش',
            onPressed: section == null ? null :
                () => configure(section: section),
            icon: const Icon(Icons.settings_rounded,
              color: GozarPalette.muted)),
        ]),
      ),
      if (section != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(child: Text(
              section.apps.length.toString() + ' برنامه · ' +
                  section.columns.toString() + ' ستون',
              style: const TextStyle(
                color: GozarPalette.muted, fontSize: 11))),
            TextButton.icon(
              key: const ValueKey('gozar-launcher-add-apps'),
              onPressed: () => addApps(section),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
              label: const Text('افزودن برنامه'),
            ),
          ]),
        ),
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
          onPageChanged: (index) => setState(() { active = index; }),
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
