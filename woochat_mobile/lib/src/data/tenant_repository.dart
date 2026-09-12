import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/tenant_context.dart';
import 'supabase_client.dart';

/// Thrown when a signed-in user has no resolvable tenant.
class TenantResolutionException implements Exception {
  const TenantResolutionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Resolves the signed-in user's tenant and role using the *existing*
/// `tenant_admin_id(p_user uuid)` function and `user_roles` table.
class TenantRepository {
  const TenantRepository();

  Future<TenantContext> resolveForCurrentUser() async {
    final user = db.auth.currentUser;
    if (user == null) {
      throw const TenantResolutionException('Not signed in.');
    }

    final tenantAdminId = await _fetchTenantAdminId(user.id);
    if (tenantAdminId == null || tenantAdminId.isEmpty) {
      throw const TenantResolutionException(
        'No tenant is linked to this account. Ask your administrator to '
        'add you to a workspace.',
      );
    }

    return TenantContext(
      authUserId: user.id,
      email: user.email,
      tenantAdminId: tenantAdminId,
      role: await _fetchHighestRole(user.id),
    );
  }

  Future<String?> _fetchTenantAdminId(String userId) async {
    final result = await db.rpc<dynamic>(
      Db.tenantAdminIdFn,
      params: <String, dynamic>{Db.tenantAdminIdParam: userId},
    );
    // The function returns a scalar uuid; some PostgREST shapes wrap it.
    if (result is String) return result;
    if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is String) return first;
      if (first is Map) return first.values.first?.toString();
    }
    if (result is Map && result.isNotEmpty) {
      return result.values.first?.toString();
    }
    return null;
  }

  /// A user may hold several rows in `user_roles`; the highest one wins.
  Future<AppRole> _fetchHighestRole(String userId) async {
    try {
      final rows = await db
          .from(Db.userRoles)
          .select('role')
          .eq('user_id', userId) as List<dynamic>;

      final roles = rows
          .whereType<Map<String, dynamic>>()
          .map((row) => AppRole.fromWire(row['role'] as String?))
          .toList();

      if (roles.isEmpty) return AppRole.user;
      roles.sort((a, b) => b.rank.compareTo(a.rank));
      return roles.first;
    } on PostgrestException {
      // Role is presentational only in Phase 1 — never block sign-in on it.
      return AppRole.user;
    }
  }
}
