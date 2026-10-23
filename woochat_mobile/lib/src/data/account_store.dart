import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// An account signed in on this phone, kept so the user can switch back to
/// it without the password.
class SavedAccount {
  const SavedAccount({
    required this.userId,
    required this.email,
    required this.refreshToken,
    this.roleLabel,
  });

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    userId: json['userId'] as String,
    email: (json['email'] as String?) ?? '',
    refreshToken: json['refreshToken'] as String,
    roleLabel: json['roleLabel'] as String?,
  );

  final String userId;
  final String email;

  /// The latest one Supabase issued. Each refresh rotates it, so it is
  /// rewritten on every token event of the account in use.
  final String refreshToken;

  /// "Admin", "User"… as it was when the account was last in use.
  final String? roleLabel;

  SavedAccount copyWith({
    String? email,
    String? refreshToken,
    String? roleLabel,
  }) => SavedAccount(
    userId: userId,
    email: email ?? this.email,
    refreshToken: refreshToken ?? this.refreshToken,
    roleLabel: roleLabel ?? this.roleLabel,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'email': email,
    'refreshToken': refreshToken,
    if (roleLabel != null) 'roleLabel': roleLabel,
  };
}

/// The accounts signed in on this phone, in the order they were added.
///
/// Supabase keeps one session at a time — and keeps it in the same shared
/// preferences — so the other accounts' refresh tokens sit here beside it,
/// no more exposed than the active one already is.
class AccountStore {
  AccountStore({Future<SharedPreferencesWithCache> Function()? prefs})
    : _prefs = prefs ?? _defaultPrefs;

  static final AccountStore instance = AccountStore();

  static const String _key = 'woochat.saved_accounts.v1';

  final Future<SharedPreferencesWithCache> Function() _prefs;

  static Future<SharedPreferencesWithCache> _defaultPrefs() =>
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{_key},
        ),
      );

  Future<List<SavedAccount>> all() async {
    final raw = (await _prefs()).getString(_key);
    if (raw == null || raw.isEmpty) return const <SavedAccount>[];
    try {
      return <SavedAccount>[
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) SavedAccount.fromJson(item),
      ];
    } catch (_) {
      // A corrupt list only costs the switcher; the active session is
      // Supabase's own and unaffected.
      return const <SavedAccount>[];
    }
  }

  Future<SavedAccount?> find(String userId) async {
    for (final account in await all()) {
      if (account.userId == userId) return account;
    }
    return null;
  }

  /// Adds the account, or refreshes what is known about it.
  Future<void> upsert({
    required String userId,
    required String refreshToken,
    String? email,
    String? roleLabel,
  }) async {
    final accounts = List<SavedAccount>.of(await all());
    final index = accounts.indexWhere((a) => a.userId == userId);
    if (index == -1) {
      accounts.add(
        SavedAccount(
          userId: userId,
          email: email ?? '',
          refreshToken: refreshToken,
          roleLabel: roleLabel,
        ),
      );
    } else {
      final current = accounts[index];
      // Skip the write when nothing changed — token events are frequent.
      if (current.refreshToken == refreshToken &&
          (email == null || email == current.email) &&
          (roleLabel == null || roleLabel == current.roleLabel)) {
        return;
      }
      accounts[index] = current.copyWith(
        email: email,
        refreshToken: refreshToken,
        roleLabel: roleLabel,
      );
    }
    await _write(accounts);
  }

  Future<void> remove(String userId) async {
    final accounts = (await all()).where((a) => a.userId != userId).toList();
    await _write(accounts);
  }

  Future<void> clear() async => (await _prefs()).remove(_key);

  Future<void> _write(List<SavedAccount> accounts) async {
    await (await _prefs()).setString(
      _key,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }
}
