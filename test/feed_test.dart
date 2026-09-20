import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telegram_news/models.dart';
import 'package:telegram_news/state.dart';

class FakeRepository extends NewsRepository {
  final requests = <Completer<PostPage>>[];
  FakeRepository() : super(http.Client());
  @override
  Future<PostPage> page({String query = '', String? cursor}) {
    final result = Completer<PostPage>();
    requests.add(result);
    return result.future;
  }
}

Post post(String id) =>
    Post(id: id, title: id, text: id, html: id, url: '', date: DateTime(2026));
void main() {
  late FakeRepository repository;
  late FeedController controller;
  setUp(() {
    repository = FakeRepository();
    controller = FeedController(repository);
  });
  tearDown(() {
    controller.dispose();
    repository.client.close();
  });
  test('a slow previous search cannot overwrite a newer search', () async {
    final first = controller.refresh(query: 'old');
    final second = controller.refresh(query: 'new');
    repository.requests[1].complete(PostPage([post('2')], null));
    await second;
    repository.requests[0].complete(PostPage([post('1')], null));
    await first;
    expect(controller.state.query, 'new');
    expect(controller.state.posts.single.id, '2');
  });
  test('pagination deduplicates posts and stops at the last page', () async {
    final first = controller.refresh();
    repository.requests[0].complete(PostPage([post('3'), post('2')], '2'));
    await first;
    final next = controller.more();
    repository.requests[1].complete(PostPage([post('2'), post('1')], null));
    await next;
    expect(controller.state.posts.map((p) => p.id), ['3', '2', '1']);
    await controller.more();
    expect(repository.requests.length, 2);
  });
  test('polling restarts the cursor when new posts exceed one page', () async {
    final first = controller.refresh();
    repository.requests[0].complete(PostPage([post('1')], null));
    await first;
    final poll = controller.refresh(silent: true);
    repository.requests[1].complete(PostPage([post('30'), post('29')], '29'));
    await poll;
    expect(controller.state.cursor, '29');
    expect(controller.state.posts.map((p) => p.id), ['30', '29']);
  });
  test('failed pagination retains content and cursor for retry', () async {
    final first = controller.refresh();
    repository.requests[0].complete(PostPage([post('2')], '2'));
    await first;
    final next = controller.more();
    repository.requests[1].completeError(StateError('offline'));
    await next;
    expect(controller.state.posts.single.id, '2');
    expect(controller.state.cursor, '2');
    expect(controller.state.error, isNotNull);
  });
}
