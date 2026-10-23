import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:woochat_mobile/src/data/account_store.dart';

// The accounts signed in on this phone, behind More → switch account.
void main() {
  late AccountStore store;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    store = AccountStore(prefs: () async => prefs);
  });

  test('keeps accounts in the order they were added', () async {
    await store.upsert(userId: 'a', refreshToken: 't1', email: 'a@x.in');
    await store.upsert(userId: 'b', refreshToken: 't2', email: 'b@x.in');
    expect((await store.all()).map((a) => a.email), <String>[
      'a@x.in',
      'b@x.in',
    ]);
  });

  test('a token refresh replaces the token, keeping the rest', () async {
    await store.upsert(
      userId: 'a',
      refreshToken: 't1',
      email: 'a@x.in',
      roleLabel: 'Admin',
    );
    await store.upsert(userId: 'a', refreshToken: 't9');
    final a = (await store.find('a'))!;
    expect(a.refreshToken, 't9');
    expect(a.email, 'a@x.in');
    expect(a.roleLabel, 'Admin');
    expect(await store.all(), hasLength(1));
  });

  test('signing an account out removes only that one', () async {
    await store.upsert(userId: 'a', refreshToken: 't1');
    await store.upsert(userId: 'b', refreshToken: 't2');
    await store.remove('a');
    expect((await store.all()).map((a) => a.userId), <String>['b']);
    expect(await store.find('a'), isNull);
  });
}
