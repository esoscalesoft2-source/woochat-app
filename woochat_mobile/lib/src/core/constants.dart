/// Values that mirror the existing backend schema.
///
/// Nothing here creates or alters schema — these are the string literals the
/// existing tables/enums already use, kept in one place so a backend rename
/// only needs a single edit here.
class Db {
  const Db._();

  // Tables
  static const String chats = 'chats';
  static const String messages = 'messages';
  static const String userRoles = 'user_roles';

  /// Saved replies behind the composer's slash menu.
  static const String shortcuts = 'shortcuts';

  /// Written by "Convert to Lead"; the Leads module itself is still a
  /// placeholder, so nothing here reads it back.
  static const String leads = 'leads';

  // Reference tables behind the "More filters" dropdown.
  static const String labels = 'labels';
  static const String chatLabels = 'chat_labels';
  static const String categories = 'categories';
  static const String chatCategories = 'chat_categories';
  static const String customerCollections = 'customer_collections';
  static const String adProductMap = 'ad_product_map';
  static const String products = 'products';
  static const String automations = 'automations';
  static const String notes = 'notes';
  static const String contactNotes = 'contact_notes';

  /// Written summaries of a conversation, one row each.
  static const String chatSummaries = 'chat_summaries';

  /// Every stage move of a lead, written by a trigger on `leads`. Read-only
  /// from the app — there is no insert policy.
  static const String leadStageEvents = 'lead_stage_events';

  /// The tenant's pipeline columns: a stage's stored `value` and the `label`
  /// the board shows for it.
  static const String leadPipelineStages = 'lead_pipeline_stages';
  static const String whatsappConnections = 'whatsapp_connections';
  static const String whatsappTemplates = 'whatsapp_templates';

  /// Reusable {{n}} names offered while composing a template.
  static const String templateParameters = 'template_parameters';

  // RPCs (existing)
  static const String tenantAdminIdFn = 'tenant_admin_id';
  static const String tenantAdminIdParam = 'p_user';

  /// No arguments. SECURITY DEFINER — it already applies tenant and assignment
  /// rules, so callers must not add their own user filter on top.
  ///
  /// Not present in the generated `types.ts`, which is stale; see
  /// `supabase/migrations/20260813100000_scheduled_failed_active_only.sql`.
  static const String scheduledChatIdsFn = 'scheduled_chat_ids';

  /// No arguments. Returns the contact directory keyed by normalised phone.
  static const String chatContactDirectoryFn = 'chat_contact_directory';

  /// No arguments. Returns an array of chat ids that arrived from an ad.
  static const String adSourcedChatIdsFn = 'ad_sourced_chat_ids';

  /// Optional `p_start` / `p_end` ISO timestamps; called with no params to mean
  /// the server's own default window. Returns `{ failed: [], replied: [] }`.
  /// No arguments. The tenant admin's connection, for team members who have no
  /// `whatsapp_connections` row of their own. Returns safe fields only.
  static const String tenantWhatsappConnectionFn =
      'get_tenant_whatsapp_connection';

  static const String funnelChatIdsFn = 'funnel_chat_ids';

  /// No arguments. `user_id` + `full_name` for everyone in the caller's
  /// tenant, for putting a name to a user id in a history.
  static const String listTenantMemberNamesFn = 'list_tenant_member_names';
  static const String funnelStartParam = 'p_start';
  static const String funnelEndParam = 'p_end';

  /// Team member profiles, used to name the ids behind an assignment.
  static const String profiles = 'profiles';

  /// The column on `chats` holding the assigned team member's user id.
  static const String assignedToColumn = 'assigned_to';

  /// Reassigns a set of chats at once, logging each move.
  static const String transferChatsBulkFn = 'transfer_chats_bulk';

  /// A tenant admin's own staff, with their WhatsApp number and flags.
  static const String listCustomersForAdminFn = 'list_customers_for_admin';

  /// The existing storage bucket the web app already writes chat media into.
  static const String attachmentsBucket = 'chat-attachments';

  // Edge functions (existing)
  static const String whatsappSendFn = 'whatsapp-send';

  /// Creates a template and submits it to Meta for every connected account.
  static const String whatsappTemplateFn = 'whatsapp-template';

  /// WhatsApp calls: permission, start, hang up. Also Meta's calls webhook.
  static const String callRouterFn = 'call-router';

  /// One row per WhatsApp call, followed over Realtime while it rings.
  static const String calls = 'calls';
}

/// `messages.direction` values.
class MessageDirection {
  const MessageDirection._();
  static const String inbound = 'inbound';
  static const String outbound = 'outbound';
}

/// `messages.status` / `chats.last_message_status` values.
class MessageStatus {
  const MessageStatus._();

  /// What an outbound row is written as before the edge function reports back.
  static const String sending = 'sending';
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String read = 'read';
  static const String failed = 'failed';

  /// Waiting for `scheduled-message-sender` to claim it at `scheduled_at`.
  static const String scheduled = 'scheduled';
}

/// `messages.send_error_code` values the app reads.
class SendErrorCode {
  const SendErrorCode._();

  /// Meta refused with 131049: the customer has hit their marketing-message
  /// cap. The sender re-queues the row twelve hours on, again and again,
  /// until it goes.
  static const String metaMarketingCap = 'META_131049';
}

/// `user_roles.role` — the existing `app_role` enum.
enum AppRole {
  superAdmin('super_admin'),
  admin('admin'),
  moderator('moderator'),
  user('user');

  const AppRole(this.wire);

  /// The exact value stored in the `app_role` enum column.
  final String wire;

  static AppRole fromWire(String? value) {
    for (final role in AppRole.values) {
      if (role.wire == value) return role;
    }
    return AppRole.user;
  }

  String get label => switch (this) {
        AppRole.superAdmin => 'Super Admin',
        AppRole.admin => 'Admin',
        AppRole.moderator => 'Moderator',
        AppRole.user => 'User',
      };

  /// Rank used when a user holds more than one row in `user_roles`.
  int get rank => switch (this) {
        AppRole.superAdmin => 3,
        AppRole.admin => 2,
        AppRole.moderator => 1,
        AppRole.user => 0,
      };
}

/// What the Settings page says about the build. Kept by hand beside
/// `pubspec.yaml`'s `version:` — bump both together.
class AppInfo {
  const AppInfo._();
  static const String version = '1.0.0';
}
