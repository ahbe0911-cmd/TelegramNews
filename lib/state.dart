import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

const channelUsername = 'ahbe1400';
const channelUrl = 'https://t.me/$channelUsername';
const apiBase = String.fromEnvironment('API_BASE_URL');
const firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED');
const appTitle = String.fromEnvironment('APP_TITLE', defaultValue: 'نبض خبر');
final prefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());
final darkProvider = StateProvider<bool>(
    (ref) => ref.read(prefsProvider).getBool('dark') ?? false);
final pushStatusProvider = StateProvider<String>(
    (ref) => firebaseEnabled ? 'در حال اتصال…' : 'Firebase متصل نشده است');
final settingsProvider = StateNotifierProvider<SettingsController, Settings>(
    (ref) => SettingsController(ref.read(prefsProvider)));

class Settings {
  final bool enabled, importantOnly, quiet;
  final int start, end;
  const Settings(
      {this.enabled = true,
      this.importantOnly = false,
      this.quiet = false,
      this.start = 1320,
      this.end = 480});
}

class SettingsController extends StateNotifier<Settings> {
  final SharedPreferences prefs;
  SettingsController(this.prefs)
      : super(Settings(
            enabled: prefs.getBool('notifications') ?? true,
            importantOnly: prefs.getBool('important') ?? false,
            quiet: prefs.getBool('quiet') ?? false,
            start: prefs.getInt('start') ?? 1320,
            end: prefs.getInt('end') ?? 480));
  Future<void> update(
      {bool? enabled,
      bool? importantOnly,
      bool? quiet,
      int? start,
      int? end}) async {
    state = Settings(
        enabled: enabled ?? state.enabled,
        importantOnly: importantOnly ?? state.importantOnly,
        quiet: quiet ?? state.quiet,
        start: start ?? state.start,
        end: end ?? state.end);
    await prefs.setBool('notifications', state.enabled);
    await prefs.setBool('important', state.importantOnly);
    await prefs.setBool('quiet', state.quiet);
    await prefs.setInt('start', state.start);
    await prefs.setInt('end', state.end);
  }
}

class PostPage {
  final List<Post> items;
  final String? cursor;
  PostPage(this.items, this.cursor);
}

class NewsRepository {
  final http.Client client;
  NewsRepository(this.client);
  Uri uri(String path, [Map<String, String>? query]) {
    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    final result = Uri.parse('$base/$path').replace(queryParameters: query);
    if (result.scheme != 'https')
      throw StateError('API_BASE_URL must use HTTPS');
    return result;
  }

  Future<PostPage> page({String query = '', String? cursor}) async {
    if (apiBase.isEmpty)
      return PostPage(
          demoPosts
              .where((p) => '${p.title} ${p.text}'.contains(query))
              .toList(),
          null);
    final response = await client
        .get(uri('posts', {'q': query, if (cursor != null) 'cursor': cursor}))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw StateError('HTTP ${response.statusCode}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PostPage(
        (data['posts'] as List)
            .map((p) => Post.fromJson(p as Map<String, dynamic>))
            .toList(),
        data['nextCursor'] as String?);
  }

  Future<Post> post(String id) async {
    if (apiBase.isEmpty) return demoPosts.firstWhere((p) => p.id == id);
    final response = await client
        .get(uri('posts/${Uri.encodeComponent(id)}'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw StateError('HTTP ${response.statusCode}');
    return Post.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}

final repositoryProvider = Provider<NewsRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return NewsRepository(client);
});

class Feed {
  final List<Post> posts;
  final bool loading;
  final String query;
  final String? cursor, error;
  const Feed(
      {this.posts = const [],
      this.loading = false,
      this.query = '',
      this.cursor,
      this.error});
}

final feedProvider = StateNotifierProvider<FeedController, Feed>(
    (ref) => FeedController(ref.read(repositoryProvider)));

class FeedController extends StateNotifier<Feed> {
  final NewsRepository repo;
  int _generation = 0;
  FeedController(this.repo) : super(const Feed());
  Future<void> refresh({String? query, bool silent = false}) async {
    if (silent && state.loading) return;
    final generation = ++_generation;
    final q = query ?? state.query;
    final previous = state;
    state = Feed(
        posts: q == previous.query ? previous.posts : [],
        loading: true,
        query: q,
        cursor: previous.cursor);
    try {
      final page = await repo.page(query: q);
      if (!mounted || generation != _generation) return;
      final previousIds = previous.posts.map((post) => post.id).toSet();
      // If an entire page arrived between polls, restart pagination so no gap is hidden.
      final merge =
          silent && page.items.any((post) => previousIds.contains(post.id));
      final posts = merge
          ? {
              for (final p in previous.posts) p.id: p,
              for (final p in page.items) p.id: p
            }.values.toList()
          : page.items;
      posts.sort((a, b) => int.parse(b.id).compareTo(int.parse(a.id)));
      state = Feed(
          posts: posts,
          query: q,
          cursor: merge ? previous.cursor : page.cursor);
    } catch (_) {
      if (mounted && generation == _generation)
        state = Feed(
            posts: state.posts,
            query: q,
            cursor: previous.cursor,
            error: 'دریافت خبرها ممکن نشد. اتصال اینترنت را بررسی کنید.');
    }
  }

  Future<void> more() async {
    if (state.loading || state.cursor == null) return;
    final generation = _generation;
    final previous = state;
    state = Feed(
        posts: previous.posts,
        query: previous.query,
        cursor: previous.cursor,
        loading: true);
    try {
      final page =
          await repo.page(query: previous.query, cursor: previous.cursor);
      if (!mounted || generation != _generation) return;
      state = Feed(
          posts: {
            for (final p in previous.posts) p.id: p,
            for (final p in page.items) p.id: p
          }.values.toList(),
          query: previous.query,
          cursor: page.cursor);
    } catch (_) {
      if (mounted && generation == _generation)
        state = Feed(
            posts: previous.posts,
            query: previous.query,
            cursor: previous.cursor,
            error: 'ادامه خبرها دریافت نشد؛ دوباره تلاش کنید.');
    }
  }
}
