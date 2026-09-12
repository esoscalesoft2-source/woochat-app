import '../core/constants.dart';

/// Who the signed-in user is, and which tenant's data they may see.
///
/// [tenantAdminId] is whatever the existing `tenant_admin_id(p_user)` RPC
/// returns for this user — every `chats` / `messages` query is scoped to it
/// via the `user_id` column.
class TenantContext {
  const TenantContext({
    required this.authUserId,
    required this.email,
    required this.tenantAdminId,
    required this.role,
  });

  final String authUserId;
  final String? email;
  final String tenantAdminId;
  final AppRole role;

  /// True when this user is the tenant owner rather than a team member.
  bool get isTenantOwner => authUserId == tenantAdminId;
}
