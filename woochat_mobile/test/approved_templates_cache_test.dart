import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:woochat_mobile/src/data/approved_templates_cache.dart';
import 'package:woochat_mobile/src/data/templates_repository.dart';

void main() {
  late SharedPreferencesWithCache prefs;
  late int fullReads;
  late int fingerprintReads;
  late List<MessageTemplate> server;

  MessageTemplate t(String id, {String at = '2026-09-01T00:00:00Z'}) =>
      MessageTemplate(
        id: id,
        name: 'tpl_$id',
        language: 'en_US',
        body: 'Hi {{1}}',
        updatedAt: at,
      );

  String fingerprint(List<MessageTemplate> list) =>
      ApprovedTemplatesCache.fingerprintOf(
        <(String, String?)>[for (final x in list) (x.id, x.updatedAt)],
      );

  ApprovedTemplatesCache cache() => ApprovedTemplatesCache(
        subscribe: false,
        prefs: () async => prefs,
        fetchAll: () async {
          fullReads++;
          return server;
        },
        fetchFingerprint: () async {
          fingerprintReads++;
          return fingerprint(server);
        },
      );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    fullReads = 0;
    fingerprintReads = 0;
    server = <MessageTemplate>[t('a'), t('b')];
  });

  test('first ever open reads the server once and saves the copy', () async {
    final c = cache();
    final list = await c.get();

    expect(list.map((x) => x.name), <String>['tpl_a', 'tpl_b']);
    expect(fullReads, 1);
    expect(prefs.getString('templates:approved'), isNotNull);

    // Opening the sheet again and again in the same session costs nothing.
    await c.get();
    await c.get();
    expect(fullReads, 1);
    expect(fingerprintReads, 0);
  });

  test('next session serves the saved copy and only checks the fingerprint',
      () async {
    await cache().get(); // session 1 saves it
    fullReads = 0;

    final c = cache(); // session 2: memory empty, disk full
    final list = await c.get();
    expect(list.map((x) => x.id), <String>['a', 'b']);
    // Served from disk — the full read was not needed…
    expect(fullReads, 0);
    // …and the background check found nothing changed.
    await Future<void>.delayed(Duration.zero);
    expect(fingerprintReads, 1);
    expect(fullReads, 0);
  });

  test('a new template on the server is picked up on the next session',
      () async {
    await cache().get();
    fullReads = 0;

    server = <MessageTemplate>[t('c'), t('a'), t('b')];
    final c = cache();
    final first = await c.get();
    // The stale copy is handed back at once, not a spinner…
    expect(first.map((x) => x.id), <String>['a', 'b']);

    // …and the fingerprint mismatch triggers exactly one full read.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fullReads, 1);
    expect((await c.get()).map((x) => x.id), <String>['c', 'a', 'b']);
    expect(c.latest.value?.length, 3, reason: 'listeners hear the change');
  });

  test('an edited template changes the fingerprint too', () {
    final before = fingerprint(<MessageTemplate>[t('a')]);
    final after = fingerprint(<MessageTemplate>[t('a', at: '2026-09-19T00:00:00Z')]);
    expect(before, isNot(after));
    // Order does not matter.
    expect(
      fingerprint(<MessageTemplate>[t('a'), t('b')]),
      fingerprint(<MessageTemplate>[t('b'), t('a')]),
    );
  });

  test('offline check leaves the saved copy standing', () async {
    await cache().get();
    final c = ApprovedTemplatesCache(
      subscribe: false,
      prefs: () async => prefs,
      fetchAll: () async => throw Exception('offline'),
      fetchFingerprint: () async => throw Exception('offline'),
    );
    final list = await c.get();
    await Future<void>.delayed(Duration.zero);
    expect(list.length, 2);
  });

  test('a template round-trips through its saved form', () {
    final original = MessageTemplate(
      id: 'x',
      name: 'promo',
      language: 'ta',
      body: 'Vanakkam {{1}}',
      headerFormat: 'IMAGE',
      headerExampleUrl: 'https://x.test/h.jpg',
      updatedAt: '2026-09-19T00:00:00Z',
    );
    final back = MessageTemplate.fromMap(original.toMap());
    expect(back.id, original.id);
    expect(back.name, original.name);
    expect(back.language, original.language);
    expect(back.body, original.body);
    expect(back.headerFormat, original.headerFormat);
    expect(back.headerExampleUrl, original.headerExampleUrl);
    expect(back.updatedAt, original.updatedAt);
  });

  test('clear forgets the copy, so the next tenant reads their own', () async {
    final c = cache();
    await c.get();
    await c.clear();
    expect(prefs.getString('templates:approved'), isNull);
    await c.get();
    expect(fullReads, 2);
  });
}
