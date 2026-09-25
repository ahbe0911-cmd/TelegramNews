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
    this.columns = 4, this.iconSize = 72, this.apps = const [],
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
      id: id, title: title, columns: 4,
      iconSize: math.max(72.0, size.toDouble()), apps: apps);
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
  bool reorderMode = false;
  String draftSectionTitle = '';
  List<Map<String, String>>? cachedInstalledApps;
  DateTime? installedAppsFetchedAt;
  final Set<String> launchingApps = <String>{};

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
      // Preserve unfinished inline title edits while changing icon size,
      // columns or app order in the very same launcher section.
      if (updated.isEmpty) {
        draftSectionTitle = '';
      } else if (original.isEmpty || destination != oldPage ||
          updated[destination].title != original[oldPage].title) {
        draftSectionTitle = updated[destination].title;
      }
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
    // Reordering on the current page must never jump its scroll position.
    if (!mounted || oldPage == destination) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pages.hasClients && sections.isNotEmpty &&
          active == destination && pages.page?.round() != active) {
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
              const SizedBox(height: 8),
              const Text('چیدمان استاندارد ۴ ستونه با آیکون‌های بزرگ'),
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
          title: title, columns: 4, iconSize: 72,
        );
        await persist([...sections, next], openIndex: sections.length);
      } else {
        final index = sections.indexWhere((s) => s.id == section.id);
        if (index < 0) return;
        final updated = [...sections];
        updated[index] = updated[index].copyWith(
          title: title, columns: 4, iconSize: 72);
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
        color: const Color(0xfff5fbff),
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
        const Text('چیدمان ۴ ستونه · آیکون‌های بزرگ',
          style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
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
    if (mounted) setState(() { showSettings = false; reorderMode = false; });
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

  // A held icon opens an action sheet; it never displays a three-dot badge.
  // Move activates drag mode so the next hold-and-drag reorders the grid.
  Future<void> openAppOptions(
      GozarLauncherSection section, GozarShortcut app) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xfff7fbff),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              key: ValueKey('gozar-launcher-app-options-' + app.key),
              leading: GozarShortcutIcon(shortcut: app, size: 43),
              title: Text(app.title, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('تنظیمات میانبر برنامه'),
            ),
            ListTile(
              key: const ValueKey('gozar-launcher-action-rename'),
              leading: const Icon(Icons.edit_outlined,
                color: GozarPalette.cyan),
              title: const Text('تغییر نام'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              key: const ValueKey('gozar-launcher-action-move'),
              leading: const Icon(Icons.open_with_rounded,
                color: GozarPalette.cyan),
              title: const Text('جابه‌جایی'),
              subtitle: const Text('آیکون را نگه دارید و به جای جدید بکشید'),
              onTap: () => Navigator.pop(sheetContext, 'move'),
            ),
            ListTile(
              key: const ValueKey('gozar-launcher-action-remove'),
              leading: const Icon(Icons.remove_circle_outline_rounded,
                color: GozarPalette.red),
              title: const Text('حذف از لانچر'),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await renameApp(section, app);
        return;
      case 'move':
        setState(() { reorderMode = true; });
        return;
      case 'remove':
        await removeApp(section, app);
        return;
    }
  }

  Future<void> launchApp(GozarShortcut app) async {
    // Samsung-like launch behaviour: one tap maps to one native launch.
    // Ignore accidental double taps while Android is bringing the target
    // activity to the foreground.
    if (!launchingApps.add(app.key)) return;
    try {
      await widget.onOpenApp(app);
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        launchingApps.remove(app.key);
      });
    }
  }

  Widget appTile(GozarLauncherSection section,
      GozarShortcut app, double cellWidth, {bool interactive = true}) {
    // Four columns with large artwork. Keep the touch target generous while
    // avoiding the card-like boxes that made the previous launcher look small.
    final size = math.min(math.max(section.iconSize, 76.0), cellWidth - 4);
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        key: ValueKey('gozar-launcher-open-' + app.key),
        radius: cellWidth * .52,
        highlightShape: BoxShape.circle,
        containedInkWell: false,
        onTap: interactive && !reorderMode ? () => launchApp(app) : null,
        onLongPress: interactive && !reorderMode
            ? () => openAppOptions(section, app) : null,
        child: Semantics(
          button: true,
          label: app.title,
          child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
            SizedBox(
              height: size + 2,
              width: double.infinity,
              child: Center(child: RepaintBoundary(
                key: ValueKey('gozar-launcher-icon-' + app.key),
                child: GozarShortcutIcon(shortcut: app, size: size))),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(app.title,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GozarPalette.text, fontSize: 12,
                  height: 1.08, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget draggableAppTile(GozarLauncherSection section,
      GozarShortcut app, double cellWidth) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => reorderMode &&
          details.data != app.key &&
          section.apps.any((candidate) => candidate.key == details.data),
      onAcceptWithDetails: (details) =>
          reorderApp(section, details.data, app.key),
      builder: (context, accepted, rejected) => Container(
        decoration: accepted.isEmpty ? null : BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xffdbeeff),
          border: Border.all(color: GozarPalette.cyan, width: 2),
        ),
        child: reorderMode
            ? LongPressDraggable<String>(
                key: ValueKey('gozar-launcher-drag-' + app.key),
                data: app.key,
                delay: const Duration(milliseconds: 220),
                maxSimultaneousDrags: 1,
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: cellWidth,
                    height: cellWidth / .80,
                    child: Opacity(opacity: .90,
                      child: appTile(section, app, cellWidth,
                        interactive: false)),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: .23,
                  child: appTile(section, app, cellWidth,
                    interactive: false),
                ),
                child: appTile(section, app, cellWidth,
                  interactive: false),
              )
            : appTile(section, app, cellWidth),
      ),
    );
  }

  Widget sectionPage(GozarLauncherSection section) => LayoutBuilder(
    builder: (context, constraints) {
      const columns = 4;
      const horizontalPadding = 16.0;
      const spacing = 10.0;
      final cellWidth = math.max(0.0,
        (constraints.maxWidth - horizontalPadding * 2 -
          (columns - 1) * spacing) / columns);
      // Stable, four-column home-screen geometry; no nested AnimatedContainer
      // or oversized decorative boxes to shrink the real Android app artwork.
      return GridView.builder(
        key: ValueKey('gozar-launcher-grid-' + section.id),
        padding: const EdgeInsets.fromLTRB(
            horizontalPadding, 18, horizontalPadding, 18),
        cacheExtent: 720,
        itemCount: section.apps.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 22,
          crossAxisSpacing: spacing,
          childAspectRatio: .76,
        ),
        itemBuilder: (context, index) {
          if (index == section.apps.length) {
            return InkWell(
              key: ValueKey('gozar-launcher-grid-add-' + section.id),
              onTap: reorderMode ||
                      section.apps.length >=
                        GozarLauncherStore.maxAppsPerSection
                  ? null : () => addApps(section),
              borderRadius: BorderRadius.circular(18),
              child: Column(children: [
                SizedBox(
                  height: math.min(78.0, cellWidth - 4) + 4,
                  child: Center(child: Container(
                    width: math.min(76.0, cellWidth - 4),
                    height: math.min(76.0, cellWidth - 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      color: const Color(0xffe1f1ff),
                      border: Border.all(
                        color: GozarPalette.cyan.withOpacity(.42))),
                    child: const Icon(Icons.add_rounded,
                      color: GozarPalette.cyan, size: 35),
                  )),
                ),
                const SizedBox(height: 5),
                Text(section.apps.length >=
                    GozarLauncherStore.maxAppsPerSection
                    ? 'ظرفیت کامل' : 'افزودن',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GozarPalette.text, fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
              ]),
            );
          }
          return draggableAppTile(section, section.apps[index], cellWidth);
        },
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
        margin: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: const LinearGradient(colors: [
            Color(0xffffffff), Color(0xffeaf5ff),
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
                  fontSize: 18, fontWeight: FontWeight.w800)),
              Text(section == null ? 'بخش جدید بسازید'
                : section.apps.length.toString() + ' برنامه · ' +
                  section.columns.toString() + ' ستون',
                style: const TextStyle(
                  color: GozarPalette.muted, fontSize: 11)),
            ],
          )),
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
      if (reorderMode && section != null) Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 5),
        child: Material(
          color: const Color(0xffe1f1ff),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(children: [
              const Icon(Icons.open_with_rounded,
                color: GozarPalette.cyan, size: 19),
              const SizedBox(width: 8),
              const Expanded(child: Text('آیکون را نگه دارید و به جای جدید بکشید',
                style: TextStyle(
                  color: GozarPalette.text, fontSize: 12))),
              TextButton(
                key: const ValueKey('gozar-launcher-finish-reorder'),
                onPressed: () => setState(() { reorderMode = false; }),
                child: const Text('پایان')),
            ]),
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
          physics: reorderMode ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: sections.length,
          onPageChanged: (index) => setState(() {
            active = index;
            reorderMode = false;
            draftSectionTitle = sections[index].title;
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
