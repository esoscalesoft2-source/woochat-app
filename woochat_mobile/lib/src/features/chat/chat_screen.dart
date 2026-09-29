import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/constants.dart';
import '../../data/attachment_picker.dart';
import '../../data/attachments_repository.dart';
import '../../data/chat_assignment_repository.dart';
import '../../data/chat_tags_repository.dart';
import '../../data/chats_repository.dart';
import '../../data/contact_context_repository.dart';
import '../../data/downloads_repository.dart';
import '../../data/media_policy.dart';
import '../../data/photo_compressor.dart';
import '../../data/storage_settings.dart';
import '../../data/leads_repository.dart';
import '../../data/messages_repository.dart';
import '../../data/shortcuts_repository.dart';
import '../../data/lead_activity_repository.dart';
import '../../data/summaries_repository.dart';
import '../../data/templates_repository.dart';
import '../../models/chat.dart';
import '../../models/chat_filters.dart';
import '../../models/message.dart';
import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chats/widgets/contact_avatar.dart';
import 'forward_compose.dart';
import 'thread_items.dart';
import 'widgets/assign_chat_sheet.dart';
import 'widgets/attach_menu.dart';
import 'widgets/attachment_preview_sheet.dart';
import 'widgets/chat_tags_sheet.dart';
import 'widgets/contact_info_sheet.dart';
import 'widgets/create_quick_reply_sheet.dart';
import 'widgets/forward_sheet.dart';
import '../call/call_screen.dart';
import 'widgets/document_viewer.dart';
import 'widgets/image_viewer.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';
import 'widgets/schedule_message_sheet.dart';
import 'widgets/send_template_sheet.dart';
import 'widgets/templates_sheet.dart';
import 'widgets/voice_recorder.dart';

/// One conversation: realtime message history plus the composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chat,
    required this.tenantContext,
  });

  final Chat chat;
  final TenantContext tenantContext;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _repository = const MessagesRepository();
  final _templates = const TemplatesRepository();
  final _attachments = const AttachmentsRepository();
  final _picker = const AttachmentPicker();
  final _tags = const ChatTagsRepository();
  final _shortcuts = const ShortcutsRepository();
  final _leads = const LeadsRepository();
  final _summaries = const SummariesRepository();
  final _leadActivity = const LeadActivityRepository();
  final _downloads = DownloadsRepository();

  /// Files already on this device (by URL) and the ones being fetched, so
  /// each row can show ⬇, a spinner, or nothing.
  final _saved = <String>{};
  final _saving = <String>{};
  final _searchController = TextEditingController();

  /// The chat's labels and categories. Loaded once the thread opens; the
  /// header buttons tint themselves from it.
  ChatTags _chatTags = ChatTags.empty;
  bool _tagsLoaded = false;

  /// The Contacts record, product and notes behind this chat, for the info
  /// sheet. Loaded once the thread opens; the sheet shows what has arrived.
  final _contactContext = const ContactContextRepository();
  ContactContext _contact = ContactContext.empty;
  final _chats = const ChatsRepository();

  /// `chats.assigned_to` for this chat, and the people it can point at.
  final _assignments = const ChatAssignmentRepository();
  String? _assignedTo;
  List<TeamMember> _members = const <TeamMember>[];
  bool _assignmentLoaded = false;

  late final Stream<List<Message>> _messages = _repository.watchMessages(
    widget.chat.id,
  );

  bool _searching = false;
  String _query = '';

  /// The expired-window strip can be put away, but it comes straight back on
  /// the next thing the closed window refuses — which is the moment its
  /// explanation is wanted.
  bool _noticeHidden = false;

  /// Brings the orange notice back; the explanation is written on it, so
  /// nothing else needs saying.
  void _onWindowBlocked() {
    setState(() => _noticeHidden = false);
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
    // A change of connection or of the auto-download setting redraws the
    // thread, so pictures start or stop loading by themselves at once.
    MediaPolicy.instance.addListener(_onMediaPolicy);
    _loadTags();
    _loadAssignment();
    _loadContactContext();
  }

  Future<void> _loadContactContext() async {
    try {
      final context = await _contactContext.load(widget.chat);
      if (mounted) setState(() => _contact = context);
    } catch (_) {
      // The sheet still opens with what the chat row itself carries.
    }
  }

  Future<void> _loadAssignment() async {
    try {
      final assignedTo = await _assignments.assigneeOf(widget.chat.id);
      final members = await _assignments.members(
        // The owner and the current assignee must be offerable even if their
        // profile row is not readable from this account.
        alsoInclude: <String>{
          widget.chat.userId,
          widget.tenantContext.authUserId,
          ?assignedTo,
        },
        signedInUserId: widget.tenantContext.authUserId,
        signedInFallbackName: widget.tenantContext.email,
      );
      if (mounted) {
        setState(() {
          _assignedTo = assignedTo;
          _members = members;
        });
      }
    } catch (_) {
      // The thread still opens; the picker reports the problem when used.
    } finally {
      if (mounted) setState(() => _assignmentLoaded = true);
    }
  }

  /// The name shown under the contact, matching the "Assigned:" value in the
  /// web app's chat header.
  String? get _assignedName {
    final id = _assignedTo;
    if (id == null) return null;
    for (final member in _members) {
      if (member.userId == id) return member.name;
    }
    return 'User ${id.substring(0, id.length.clamp(0, 8))}';
  }

  Future<void> _openAssign() async {
    if (!_assignmentLoaded) return;

    final result = await showAssignChatSheet(
      context,
      members: _members,
      assignedTo: _assignedTo,
      onAssign: (userId) async {
        try {
          await _assignments.assign(widget.chat.id, userId);
          return true;
        } on ChatAssignmentException catch (error) {
          _showError(error.message);
          return false;
        } catch (error) {
          _showError('Could not change the assignment: $error');
          return false;
        }
      },
    );

    if (result != null && mounted) {
      setState(() => _assignedTo = result.userId);
    }
  }

  @override
  void dispose() {
    MediaPolicy.instance.removeListener(_onMediaPolicy);
    _searchController.dispose();
    super.dispose();
  }

  void _onMediaPolicy() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _tags.load(widget.chat.id);
      if (mounted) setState(() => _chatTags = tags);
    } catch (_) {
      // The thread itself must still open — the pickers say what is wrong
      // when they are actually used.
    } finally {
      if (mounted) setState(() => _tagsLoaded = true);
    }
  }

  Future<void> _openLabels() => _openTagPicker(
    title: 'Labels',
    emptyMessage: 'No labels exist in this workspace yet.',
    options: <TagOption>[
      for (final label in _chatTags.labels)
        TagOption(id: label.id, name: label.name, color: label.color),
    ],
    selected: _chatTags.labelIds,
    write: (id, applied) => _tags.setLabel(
      widget.chat.id,
      id,
      applied: applied,
      chatOwnerId: widget.chat.userId,
      authUserId: widget.tenantContext.authUserId,
    ),
    commit: (ids) => _chatTags = _chatTags.copyWith(labelIds: ids),
  );

  Future<void> _openCategories() => _openTagPicker(
    title: 'Categories',
    emptyMessage: 'No categories exist in this workspace yet.',
    options: <TagOption>[
      for (final category in _chatTags.categories)
        TagOption(id: category.id, name: category.name, color: category.color),
    ],
    selected: _chatTags.categoryIds,
    write: (id, applied) => _tags.setCategory(
      widget.chat.id,
      id,
      applied: applied,
      chatOwnerId: widget.chat.userId,
      authUserId: widget.tenantContext.authUserId,
    ),
    commit: (ids) => _chatTags = _chatTags.copyWith(categoryIds: ids),
  );

  /// Shared plumbing for both pickers: each toggle writes immediately, and the
  /// header only follows the rows that actually landed.
  Future<void> _openTagPicker({
    required String title,
    required String emptyMessage,
    required List<TagOption> options,
    required Set<String> selected,
    required Future<void> Function(String id, bool applied) write,
    required void Function(Set<String> ids) commit,
  }) async {
    if (!_tagsLoaded) return;
    final applied = <String>{...selected};

    await showChatTagsSheet(
      context,
      title: title,
      emptyMessage: emptyMessage,
      options: options,
      selected: selected,
      onToggle: (id, on) async {
        try {
          await write(id, on);
          on ? applied.add(id) : applied.remove(id);
          return true;
        } on ChatTagException catch (error) {
          _showError(error.message);
          return false;
        } catch (error) {
          _showError('Could not update $title: $error');
          return false;
        }
      },
    );

    if (mounted) setState(() => commit(applied));
  }

  /// One overflow-menu row, with an optional count on the right.
  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    int count = 0,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: count > 0 ? Wa.accent : Wa.icon),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Wa.title),
        ),
        trailing: count > 0
            ? Text(
                '$count',
                style: const TextStyle(color: Wa.accent, fontSize: 13),
              )
            : null,
      ),
    );
  }

  /// A WhatsApp call from the business number, in the app. The call
  /// screen owns everything from here: permission, the offer, ringing,
  /// audio, hanging up.
  Future<void> _callCustomer() => showCallScreen(
        context,
        chat: widget.chat,
        name: _contact.name?.trim().isNotEmpty ?? false
            ? _contact.name!.trim()
            : widget.chat.displayName,
        photoUrl: _contact.photoUrl,
      );

  Future<void> _openContactInfo() async {
    // Labels on the chat plus any held on the contact record itself, the
    // same union the list row draws as dots.
    final labelIds = <String>{
      ..._chatTags.labelIds,
      ..._contact.contactLabelIds,
    };
    await showContactInfoSheet(
      context,
      chat: widget.chat,
      contactName: _contact.name,
      photoUrl: _contact.photoUrl,
      productName: _contact.productName,
      notes: _contact.notes,
      loadSummaries: () => _summaries.forChat(widget.chat.id),
      addSummary: (text) => _summaries.add(
        chatId: widget.chat.id,
        authUserId: widget.tenantContext.authUserId,
        text: text,
      ),
      loadLeadActivity: () => _leadActivity.forChat(widget.chat.id),
      assignedName: _assignedName,
      labels: <String>[
        for (final label in _chatTags.labels)
          if (labelIds.contains(label.id)) label.name,
      ],
      categories: <String>[
        for (final category in _chatTags.categories)
          if (_chatTags.categoryIds.contains(category.id)) category.name,
      ],
      onCopyNumber: () {
        Navigator.of(context).pop();
        unawaited(_copyPhone());
      },
      onChangeAssignee: () {
        Navigator.of(context).pop();
        _openAssign();
      },
    );
  }

  /// Writes this chat into the existing `leads` table.
  ///
  /// The Leads module itself is still a placeholder, so this only creates the
  /// row — there is nowhere in the app to see it yet.
  Future<void> _convertToLead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Wa.sheet,
        title: const Text(
          'Convert to Lead',
          style: TextStyle(color: Thread.text, fontSize: 17),
        ),
        content: Text(
          'Create a lead for ${widget.chat.displayName}? The Leads screen is '
          'not built yet, so the row will only be visible in the web app.',
          style: const TextStyle(color: Thread.meta, fontSize: 13.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Thread.text),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Wa.accent,
              foregroundColor: Colors.white,
              // The app-wide style is full width, which has no meaning in a
              // dialog's button row.
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final outcome = await _leads.convert(
        chatId: widget.chat.id,
        ownerUserId: widget.chat.userId,
        contactName: widget.chat.contactName,
        contactPhone: widget.chat.contactPhone,
        assignedTo: _assignedTo,
      );
      _notify(switch (outcome) {
        LeadOutcome.created => 'Lead created for ${widget.chat.displayName}.',
        LeadOutcome.alreadyExisted =>
          'This chat is already a lead — nothing was duplicated.',
      });
    } on LeadException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Could not convert this chat: $error');
    }
  }

  // ---- Message actions ---------------------------------------------------

  /// Holding a bubble: forward it, or copy its text.
  Future<void> _openMessageActions(Message message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Wa.sheet,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.reply, color: Wa.icon),
              title: const Text('Reply',
                  style: TextStyle(color: Wa.title, fontSize: 15)),
              onTap: () => Navigator.of(context).pop('reply'),
            ),
            ListTile(
              leading: const Icon(Icons.shortcut, color: Wa.icon),
              title: const Text('Forward',
                  style: TextStyle(color: Wa.title, fontSize: 15)),
              onTap: () => Navigator.of(context).pop('forward'),
            ),
            if (message.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: Wa.icon),
                title: const Text('Copy text',
                    style: TextStyle(color: Wa.title, fontSize: 15)),
                onTap: () => Navigator.of(context).pop('copy'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'reply':
        setState(() => _replyingTo = message);
      case 'forward':
        await _forward(message);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
        _notify('Copied');
    }
  }

  /// WhatsApp's forward: pick chats, then the message goes to each as a new
  /// outbound message. Media is forwarded by its stored URL — nothing is
  /// downloaded or uploaded again — which is exactly what the web app does.
  Future<void> _forward(Message message) async {
    final content = (message.content ?? '').trim();
    if (content.isEmpty) {
      _showError('There is nothing to forward in this message.');
      return;
    }

    // Names and photos come from the contact directory, so the picker reads
    // the same as the chat list ("Fi17281-vilokshana", not the WhatsApp name).
    Map<String, DirectoryEntry> directory = const <String, DirectoryEntry>{};
    final choice = await showForwardSheet(
      context,
      message: message,
      exclude: widget.chat,
      loadChats: () async {
        final results = await Future.wait<Object>(<Future<Object>>[
          _chats.fetchChats(tenantAdminId: widget.tenantContext.tenantAdminId),
          _contactContext.directory(),
        ]);
        directory = results[1] as Map<String, DirectoryEntry>;
        return results[0] as List<Chat>;
      },
      nameOf: (chat) {
        final name = directory[chat.normalisedPhone]?.name?.trim();
        return (name == null || name.isEmpty) ? chat.displayName : name;
      },
      photoOf: (chat) => directory[chat.normalisedPhone]?.photoUrl,
    );
    if (choice == null || choice.chats.isEmpty || !mounted) return;
    final targets = choice.chats;

    // The typed message folded in — as the caption on media, appended on
    // text — so each chat gets one message. See composeForward.
    final composed = composeForward(message, note: choice.note);
    final outgoing = composed.content;
    final media = composed.media;

    _notify(
      'Forwarding to ${targets.length} chat${targets.length == 1 ? '' : 's'}…',
    );
    var failed = 0;
    for (final target in targets) {
      try {
        await _repository.sendTextMessage(
          chatId: target.id,
          senderUserId: widget.tenantContext.authUserId,
          chatOwnerUserId: target.userId,
          content: outgoing,
          contactPhone: target.contactPhone,
          media: media,
        );
      } on MessageSendException {
        // The row is in that chat marked failed with its reason.
        failed++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    if (failed == 0) {
      _notify('Forwarded to ${targets.length} chat${targets.length == 1 ? '' : 's'}.');
    } else {
      _showError('$failed of ${targets.length} could not be sent.');
    }
  }

  /// Rows this screen inserted that the realtime feed has not echoed back
  /// yet, so a sent message is on screen the instant it is stored rather
  /// than a round trip later. Each is dropped once the feed carries it.
  final _pending = <String, Message>{};

  /// The message the next send will quote, once Reply is picked on it.
  Message? _replyingTo;

  /// Quoted messages the thread itself does not hold, fetched on demand and
  /// kept. Ids already asked for are remembered so a quote of something
  /// deleted is not re-fetched on every build.
  final _quotedExtra = <String, Message>{};
  final _quotedRequested = <String>{};

  /// Any quoted ids missing from [byId] are fetched once; the thread
  /// rebuilds with them when they land.
  void _resolveMissingQuotes(List<Message> visible, Map<String, Message> byId) {
    final missing = <String>{
      for (final message in visible)
        if (message.replyToMessageId case final id?)
          if (!byId.containsKey(id) && !_quotedRequested.contains(id)) id,
    };
    if (missing.isEmpty) return;
    _quotedRequested.addAll(missing);
    unawaited(_repository.fetchByIds(missing).then((found) {
      if (!mounted || found.isEmpty) return;
      setState(() {
        for (final message in found) {
          _quotedExtra[message.id] = message;
        }
      });
    }).catchError((Object _) {
      // Left blank rather than retried in a loop; the thread still reads.
    }));
  }

  String _authorOf(Message message) =>
      message.isOutbound ? 'You' : widget.chat.displayName;

  /// Sends typed text the way WhatsApp does: the row is stored, the box
  /// clears and the bubble shows with its clock — all in one short insert —
  /// and the slow WhatsApp round trip runs behind it. Waiting on that trip
  /// used to hold the composer for seconds on every message.
  Future<bool> _send(String text) async {
    final quoted = _replyingTo;
    final Message message;
    try {
      message = await _repository.insertOutbound(
        chatId: widget.chat.id,
        // The row is authored by whoever is signed in; the edge function needs
        // the chat's owner separately to resolve the sending number.
        senderUserId: widget.tenantContext.authUserId,
        content: text,
        replyToMessageId: quoted?.id,
      );
    } catch (error) {
      // Nothing was persisted anywhere. Keep the typed text so the user can
      // retry instead of losing it.
      _showError('Could not send the message: $error');
      return false;
    }

    if (mounted) {
      setState(() {
        _pending[message.id] = message;
        _replyingTo = null;
      });
    }
    unawaited(_deliverInBackground(message, quoted: quoted));
    return true;
  }

  Future<void> _deliverInBackground(Message message, {Message? quoted}) async {
    try {
      await _repository.deliver(
        message,
        chatOwnerUserId: widget.chat.userId,
        contactPhone: widget.chat.contactPhone,
        // WhatsApp draws the quote on the customer's phone only when told
        // which of ITS messages is being answered; a quoted message that
        // never reached WhatsApp (still sending, or failed) has no such id
        // and the reply goes out plain, as the web app's does.
        replyToWhatsAppMessageId: quoted?.whatsappMessageId,
      );
    } on MessageSendException catch (error) {
      // The row is already marked failed, so the bubble shows the reason;
      // the toast just makes sure it is noticed.
      _showError(error.message);
    }
  }

  /// One item of an outbound set: what the row stores, and the media (by
  /// URL) WhatsApp is handed for it.
  ///
  /// Sends a set the way WhatsApp feels: ONE insert puts every bubble on
  /// screen at once, then every WhatsApp call fires together in the
  /// background and each tick updates as Meta answers. Waiting on each
  /// round-trip in turn is what made a photo set crawl out one at a time.
  Future<void> _dispatchSet(
    List<({String content, OutboundMedia? media})> items, {
    Message? quoted,
  }) async {
    if (items.isEmpty) return;
    final List<Message> rows;
    try {
      rows = await _repository.insertOutboundMany(
        chatId: widget.chat.id,
        senderUserId: widget.tenantContext.authUserId,
        contents: <String>[for (final item in items) item.content],
        replyToMessageId: quoted?.id,
      );
    } catch (error) {
      _showError('Could not send: $error');
      return;
    }
    if (mounted) {
      setState(() {
        for (final row in rows) {
          _pending[row.id] = row;
        }
        _replyingTo = null;
      });
    }

    // All at once, not one after another. Failures are already on their
    // bubbles; one toast covers the lot.
    unawaited(() async {
      var failed = 0;
      await Future.wait(<Future<void>>[
        for (var i = 0; i < rows.length; i++)
          _repository
              .deliver(
                rows[i],
                chatOwnerUserId: widget.chat.userId,
                contactPhone: widget.chat.contactPhone,
                media: items[i].media,
                replyToWhatsAppMessageId:
                    i == 0 ? quoted?.whatsappMessageId : null,
              )
              .catchError((Object _) => failed++),
      ]);
      if (failed > 0 && mounted) {
        _showError(
          rows.length == 1
              ? 'The message could not be sent — see the reason on it.'
              : '$failed of ${rows.length} could not be sent — see the '
                  'reasons on them.',
        );
      }
    }());
  }

  /// Older messages paged in above the live feed, oldest first.
  final _older = <Message>[];
  bool _loadingOlder = false;

  /// False once a page comes back short — there is nothing further back.
  bool _mayHaveOlder = true;

  Future<void> _loadOlder(List<Message> shown) async {
    if (_loadingOlder || !_mayHaveOlder || shown.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _repository.fetchMessages(
        widget.chat.id,
        before: shown.first.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _older.insertAll(0, page);
        _mayHaveOlder = page.length >= MessagesRepository.livePageSize;
      });
    } catch (error) {
      _showError('Could not load earlier messages: $error');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// The feed plus pages loaded above it and anything sent from here that
  /// it has not caught up with.
  List<Message> _withPending(List<Message> fromFeed) {
    final merged = mergeThread(
      feed: fromFeed,
      older: _older,
      pending: _pending,
    );
    if (merged.caughtUp.isNotEmpty) {
      // Not inside build: the feed has caught up, so forget the overlay on
      // the next frame rather than mutating state mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => merged.caughtUp.forEach(_pending.remove));
      });
    }
    return merged.messages;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// WhatsApp allows free-form replies only within 24 hours of the contact's
  /// last inbound message. Derived from the live stream so the input
  /// re-enables the moment a new inbound message lands.
  bool _windowOpen(List<Message> messages) {
    DateTime? lastInbound;
    for (final message in messages) {
      if (message.direction == MessageDirection.inbound &&
          message.createdAt != null) {
        final at = message.createdAt!;
        if (lastInbound == null || at.isAfter(lastInbound)) lastInbound = at;
      }
    }
    lastInbound ??= widget.chat.lastInboundAt;
    if (lastInbound == null) return false;
    return DateTime.now().difference(lastInbound) < const Duration(hours: 24);
  }

  Future<void> _openTemplates() async {
    final template = await showTemplatesSheet(
      context,
      load: _templates.fetchApproved,
      chatName: widget.chat.displayName,
      loadParameters: _templates.fetchSavedParameters,
      saveParameter: (name) => _templates.saveParameter(
        name: name,
        createdBy: widget.tenantContext.authUserId,
      ),
      create: _templates.createTemplate,
    );
    if (template == null || !mounted) return;

    final values = await showSendTemplateSheet(
      context,
      template: template,
      chatName: widget.chat.displayName,
    );
    if (values == null || !mounted) return;

    try {
      await _repository.sendTemplateMessage(
        chatId: widget.chat.id,
        senderUserId: widget.tenantContext.authUserId,
        chatOwnerUserId: widget.chat.userId,
        contactPhone: widget.chat.contactPhone,
        template: template,
        values: values,
      );
      _notify('Template sent');
    } on MessageSendException catch (error) {
      _notify(error.message);
    }
  }

  /// Uploads a finished recording into the existing bucket, then sends it as
  /// an ordinary outbound message carrying an audio attachment marker.
  Future<bool> _sendVoiceNote(VoiceClip clip) async {
    final String url;
    try {
      url = await _attachments.upload(
        authUserId: widget.tenantContext.authUserId,
        chatId: widget.chat.id,
        fileName: clip.fileName,
        bytes: clip.bytes,
        contentType: clip.contentType,
      );
    } on AttachmentUploadException catch (error) {
      _showError(error.message);
      return false;
    }
    await _dispatchSet(<({String content, OutboundMedia? media})>[
      (
        // The marker is what the row stores so the thread can draw a
        // player; WhatsApp gets the file through the media keys instead.
        content: Message.attachmentMarker(
          type: 'audio',
          name: clip.fileName,
          url: url,
        ),
        media: OutboundMedia(
          url: url,
          type: 'audio',
          mimeType: clip.contentType,
          fileName: clip.fileName,
        ),
      ),
    ]);
    return true;
  }

  /// Opens the right device picker for the chosen attach option, previews
  /// what came back, then uploads and sends it.
  Future<void> _onAttach(AttachOption option) async {
    try {
      if (option == AttachOption.contact) {
        await _shareContact();
        return;
      }

      // Photos & Videos takes up to fifteen at once; the rest pick one.
      final List<PickedAttachment> picked;
      if (option == AttachOption.photos) {
        picked = await _picker.pickPhotosOrVideos();
      } else {
        final one = await switch (option) {
          AttachOption.camera => _picker.takePhoto(),
          AttachOption.audio => _picker.pickAudio(),
          AttachOption.document => _picker.pickDocument(),
          // Contact is handled above; the other three never reach here —
          // the composer routes them before calling this.
          AttachOption.photos ||
          AttachOption.contact ||
          AttachOption.template ||
          AttachOption.quickReply =>
            Future<PickedAttachment?>.value(),
        };
        picked = <PickedAttachment>[?one];
      }
      if (picked.isEmpty || !mounted) return;

      final choice = await showAttachmentsPreviewSheet(
        context,
        attachments: picked,
        chatName: widget.chat.displayName,
        // The + in the sheet opens the same picker again and the pick joins
        // the set — so a photo set can be built up a few at a time.
        onAddMore: (remaining) async => switch (option) {
          AttachOption.photos =>
            (await _picker.pickPhotosOrVideos()).take(remaining).toList(),
          AttachOption.camera => <PickedAttachment>[?await _picker.takePhoto()],
          AttachOption.audio => <PickedAttachment>[?await _picker.pickAudio()],
          AttachOption.document =>
            <PickedAttachment>[?await _picker.pickDocument()],
          _ => const <PickedAttachment>[],
        },
      );
      if (choice == null || choice.attachments.isEmpty || !mounted) return;

      await _sendAttachments(choice.attachments, caption: choice.caption);
    } on AttachmentPickerException catch (error) {
      _showError(error.message);
    }
  }

  /// Uploads every file at once, then sends the set: caption on the first,
  /// the rest bare, in the order they were picked. The sheet has already
  /// closed; the bubbles appear together the moment the rows land.
  Future<void> _sendAttachments(
    List<PickedAttachment> picked, {
    required String caption,
  }) async {
    // Standard quality (the default, as on WhatsApp) shrinks photos before
    // they go up; HD sends them as picked. Settings → Storage and data.
    final attachments =
        StorageSettings.instance.uploadQuality == UploadQuality.standard
            ? await Future.wait(picked.map(PhotoCompressor.standardQuality))
            : picked;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final List<String?> urls;
    try {
      urls = await Future.wait(<Future<String?>>[
        for (var i = 0; i < attachments.length; i++)
          _attachments
              .upload(
                authUserId: widget.tenantContext.authUserId,
                chatId: widget.chat.id,
                // Two files picked with the same name would otherwise
                // overwrite each other in the bucket.
                fileName: '${stamp}_${i}_${attachments[i].fileName}',
                bytes: attachments[i].bytes,
                contentType: attachments[i].mimeType,
              )
              .then<String?>((url) => url, onError: (Object _) => null),
      ]);
    } catch (error) {
      _showError('Could not upload: $error');
      return;
    }

    final items = <({String content, OutboundMedia? media})>[];
    var lost = 0;
    for (var i = 0; i < attachments.length; i++) {
      final url = urls[i];
      if (url == null) {
        lost++;
        continue;
      }
      final file = attachments[i];
      final text = i == 0 ? caption : '';
      items.add((
        // The marker is what the row stores so the thread can render the
        // file; WhatsApp gets it through the media keys instead.
        content: Message.attachmentMarker(
          type: file.type,
          name: file.fileName,
          url: url,
          caption: text,
        ),
        media: OutboundMedia(
          url: url,
          type: file.type,
          mimeType: file.mimeType,
          fileName: file.fileName,
          caption: text,
        ),
      ));
    }
    if (lost > 0) {
      _showError(
        lost == attachments.length
            ? 'The upload failed. Check the connection and try again.'
            : '$lost of ${attachments.length} could not be uploaded.',
      );
    }
    await _dispatchSet(items);
  }

  /// Uploads one file and sends it. Kept for the contact card.
  Future<bool> _sendAttachment(
    PickedAttachment attachment, {
    required String caption,
  }) async {
    await _sendAttachments(<PickedAttachment>[attachment], caption: caption);
    return true;
  }

  /// Shares an address-book contact.
  ///
  /// `whatsapp-send` has no contact-card branch, so the vCard is sent as a
  /// document — the customer receives a `.vcf` they can open and save, which
  /// is the whole point of sharing one.
  Future<void> _shareContact() async {
    final contact = await _picker.pickContact();
    if (contact == null || !mounted) return;

    final safeName = contact.displayName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim();
    final attachment = PickedAttachment(
      bytes: Uint8List.fromList(utf8.encode(contact.vCard)),
      fileName: '${safeName.isEmpty ? 'contact' : safeName}.vcf',
      mimeType: 'text/vcard',
      type: 'document',
    );

    final caption = await showAttachmentPreviewSheet(
      context,
      attachment: attachment,
      chatName: widget.chat.displayName,
    );
    if (caption == null || !mounted) return;

    await _sendAttachment(
      attachment,
      // Without a caption the card arrives as a bare file name; the contact's
      // own name and number read far better in the thread.
      caption: caption.isEmpty ? contact.preview : caption,
    );
  }

  /// Opens a saved quick reply for changes, on the same form that writes a
  /// new one.
  Future<QuickReply?> _editQuickReply(QuickReply reply) async {
    final updated = await showCreateQuickReplySheet(
      context,
      existing: reply,
      save: (title, message, media) => _shortcuts.update(
        id: reply.id,
        title: title,
        message: message,
        media: media,
      ),
      addMedia: _uploadQuickReplyMedia,
    );
    if (updated != null) _notify('Saved /${updated.title}.');
    return updated;
  }

  /// Sends a quick reply's staged files, then whatever is left in the message
  /// box as its own final message.
  ///
  /// The files were uploaded when the reply was created, so nothing is
  /// uploaded again — each one is sent straight from its stored URL. They go
  /// in the reply's own order, and the text follows, which is the order the
  /// web app sends a shortcut bundle in.
  Future<bool> _sendShortcutMedia(
    List<QuickReplyMedia> media,
    String caption,
  ) async {
    // Files first in the reply's own order, then the text as its own final
    // message — the order the web app sends a shortcut bundle in. Nothing
    // is uploaded: each file is sent straight from its stored URL.
    await _dispatchSet(<({String content, OutboundMedia? media})>[
      for (final item in media)
        (
          content: Message.attachmentMarker(
            type: item.type,
            name: item.name,
            url: item.url,
          ),
          media: OutboundMedia(
            url: item.url,
            type: item.type,
            mimeType: _mimeForShortcut(item),
            fileName: item.name,
          ),
        ),
      if (caption.isNotEmpty) (content: caption, media: null),
    ]);
    // The staging tray is cleared either way: every file now has a row in
    // the thread, and a failed one is retried from there, not from the tray.
    return true;
  }

  /// Shortcut media carries no stored MIME type, so it is read back off the
  /// file name the way the picker does.
  static String _mimeForShortcut(QuickReplyMedia item) =>
      AttachmentPicker.mimeForFileName(item.name, item.type);

  /// Picks one file for a quick reply and uploads it into the existing
  /// bucket, returning what was stored.
  ///
  /// The caps are the web app's own — smaller than a chat attachment's,
  /// because a shortcut's media is re-sent on every use.
  Future<QuickReplyMedia?> _uploadQuickReplyMedia(String kind) async {
    final picked = await switch (kind) {
      'image' => _picker.pickImage(),
      'audio' => _picker.pickAudio(),
      'video' => _picker.pickVideo(),
      _ => Future<PickedAttachment?>.value(),
    };
    if (picked == null) return null;

    final limit = shortcutLimitFor(kind);
    if (limit != null && picked.bytes.length > limit) {
      throw AttachmentPickerException(
        '"${picked.fileName}" is too large — the limit for $kind is '
        '${(limit / (1024 * 1024)).round()}MB.',
      );
    }

    final url = await _attachments.upload(
      authUserId: widget.tenantContext.authUserId,
      // Shortcut media is not tied to one conversation, so it is filed under
      // `shortcuts` the way the web app files it.
      chatId: 'shortcuts',
      fileName: '${DateTime.now().millisecondsSinceEpoch}_${picked.fileName}',
      bytes: picked.bytes,
      contentType: picked.mimeType,
    );

    return QuickReplyMedia(url: url, type: picked.type, name: picked.fileName);
  }

  /// The + menu's Quick Replies: a sheet that saves a new `/shortcut` to the
  /// existing `shortcuts` table, then hands it back so the composer can offer
  /// it straight away.
  Future<QuickReply?> _createQuickReply() async {
    final reply = await showCreateQuickReplySheet(
      context,
      save: (title, message, media) => _shortcuts.create(
        userId: widget.tenantContext.authUserId,
        title: title,
        message: message,
        media: media,
      ),
      addMedia: _uploadQuickReplyMedia,
    );
    if (reply != null) _notify('Saved /${reply.title}. Type / to use it.');
    return reply;
  }

  /// When the customer last wrote in, from the live thread first and the
  /// chat row as a fallback — the same derivation [_windowOpen] uses.
  DateTime? _lastInboundAt(List<Message> messages) {
    DateTime? last;
    for (final message in messages) {
      if (message.direction == MessageDirection.inbound &&
          message.createdAt != null) {
        final at = message.createdAt!;
        if (last == null || at.isAfter(last)) last = at;
      }
    }
    return last ?? widget.chat.lastInboundAt;
  }

  /// Writes the scheduled row(s). Nothing is sent from here: the server's
  /// `scheduled-message-sender` claims the row at its time. Returns true
  /// once queued, so the composer clears.
  Future<bool> _onSchedule(
    ScheduledSend scheduled,
    String draft,
    List<QuickReplyMedia> staged,
  ) async {
    final List<String> contents;
    if (scheduled.isTemplate) {
      contents = <String>[scheduled.renderedBody];
    } else if (staged.isNotEmpty) {
      // One row per staged file, exactly as a normal send stores them, with
      // the typed text as the caption on the last so it reads under the
      // set rather than before it.
      contents = <String>[
        for (var i = 0; i < staged.length; i++)
          Message.attachmentMarker(
            type: staged[i].type,
            name: staged[i].name,
            url: staged[i].url,
            caption: i == staged.length - 1 ? draft : '',
          ),
      ];
    } else {
      if (draft.isEmpty) {
        _showError('Type a message to schedule.');
        return false;
      }
      contents = <String>[draft];
    }

    try {
      final rows = await _repository.schedule(
        chatId: widget.chat.id,
        senderUserId: widget.tenantContext.authUserId,
        at: scheduled.at,
        contents: contents,
        templateName: scheduled.template?.name,
        templateLanguage: scheduled.template?.language,
        templateParams: scheduled.isTemplate ? scheduled.orderedParams : null,
      );
      if (mounted) {
        setState(() {
          for (final row in rows) {
            _pending[row.id] = row;
          }
        });
      }
      // No toast: the queued bubble with its clock and time IS the
      // confirmation, and a snackbar over it was saying the same thing
      // twice while covering the composer.
      return true;
    } catch (error) {
      _showError('Could not schedule the message: $error');
      return false;
    }
  }

  /// Pulls a queued message before the server sends it.
  Future<void> _cancelScheduled(Message message) async {
    try {
      final removed = await _repository.cancelScheduled(message.id);
      if (!mounted) return;
      if (removed) {
        setState(() => _pending.remove(message.id));
        _notify('Scheduled message canceled');
      } else {
        _showError('Too late — that message is already being sent.');
      }
    } catch (error) {
      _showError('Could not cancel: $error');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  /// A picture opens in the app's own full-screen viewer, the way WhatsApp
  /// shows one — it used to bounce out to a browser tab, which reads as the
  /// app having lost the photo. Anything else (a PDF, a video, a document)
  /// still goes to whatever the device opens it with.
  Future<void> _openAttachment(
    MessageAttachment attachment, {
    String caption = '',
  }) async {
    // Anything the app can show, it shows itself — a tap in a chat should
    // not bounce out to a browser tab. Pictures include a photo sent as a
    // document, which arrives typed "document" with a .jpg name.
    if (attachment.looksLikeImage) {
      await showImageViewer(
        context,
        attachment: attachment,
        caption: caption,
        title: widget.chat.displayName,
      );
      return;
    }
    if (attachment.isPdf) {
      await showDocumentViewer(context, attachment: attachment);
      return;
    }
    // Word, Excel and the like have no renderer here. Tapping the name used
    // to hand the link to the browser, which simply downloaded the file —
    // so a look at a document was a copy in Downloads. Saving is now the ⬇
    // on the row, and only that. Once saved, the tap opens the saved copy
    // in whatever the phone has for it.
    if (_saved.contains(attachment.url)) {
      if (kIsWeb) {
        // The browser's kept copy opens in a new tab: shown if it can be,
        // saved if not — either way it was the tap that asked.
        if (await _downloads.openKept(attachment.url)) return;
      } else {
        final path = await _downloads.localPathFor(attachment.url);
        if (path != null) {
          final result = await OpenFilex.open(path);
          if (result.type != ResultType.done) {
            _showError('Nothing on this device can open ${attachment.name}.');
          }
          return;
        }
      }
      // The copy is gone: put the ⬇ back.
      if (mounted) setState(() => _saved.remove(attachment.url));
    }
    _notify('Tap ⬇ to download ${attachment.name}.');
  }

  Future<void> _loadSaved() async {
    final urls = await _downloads.downloadedUrls();
    if (mounted) setState(() => _saved.addAll(urls));
  }

  AttachmentSaveState _saveStateOf(Message message) {
    final url = message.attachment?.url;
    if (url == null) return AttachmentSaveState.notSaved;
    if (_saving.contains(url)) return AttachmentSaveState.saving;
    return _saved.contains(url)
        ? AttachmentSaveState.saved
        : AttachmentSaveState.notSaved;
  }

  /// Files the auto-download rule already fetched or declined this visit,
  /// so a redraw does not ask twice.
  final _autoConsidered = <String>{};

  /// WhatsApp's auto-download for files: audio, videos and documents that
  /// the rule for the current connection allows are fetched as they
  /// appear, so the ⬇ is already gone by the time they are looked at —
  /// to the device on a phone, into the browser's store on the web. Only
  /// recent ones: opening an old thread must not pull a year of invoices.
  void _autoDownload(List<Message> messages) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final wanted = <Message>[
      for (final message in messages)
        if (message.attachment case final attachment?)
          // By the marker's type, not the file's name: a screenshot sent
          // AS a document shows as a file row with a ⬇, so the Documents
          // tick is the one that governs it. (Photos sent as photos load
          // inline and are governed by the Photos tick in the bubble.)
          if (MediaKind.of(attachment.type) != null &&
              MediaKind.of(attachment.type) != MediaKind.photos &&
              (message.createdAt?.isAfter(since) ?? false) &&
              !_saved.contains(attachment.url) &&
              !_saving.contains(attachment.url) &&
              !_autoConsidered.contains(attachment.url) &&
              MediaPolicy.instance.autoLoads(attachment.type))
            message,
    ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!)); // newest first
    for (final message in wanted.take(_autoDownloadBatch)) {
      final attachment = message.attachment!;
      _autoConsidered.add(attachment.url);
      // After this frame: the build must not set state on itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _downloadAttachment(attachment, quiet: true);
      });
    }
  }

  static const int _autoDownloadBatch = 10;

  /// The ⬇ on a file row: saves the file on this device and, once it is
  /// there, takes the icon away — the row is then "already yours".
  /// [quiet] is the auto-download: no toast for what nobody tapped.
  Future<void> _downloadAttachment(
    MessageAttachment attachment, {
    bool quiet = false,
  }) async {
    if (_saving.contains(attachment.url)) return;
    setState(() => _saving.add(attachment.url));
    try {
      await (quiet
          ? _downloads.prefetch(attachment)
          : _downloads.download(attachment));
      if (!mounted) return;
      setState(() {
        _saving.remove(attachment.url);
        _saved.add(attachment.url);
      });
      if (!quiet) {
        _notify(kIsWeb
            ? 'Downloading ${attachment.name}'
            : 'Saved ${attachment.name}');
      }
    } on DownloadException catch (error) {
      if (!mounted) return;
      setState(() => _saving.remove(attachment.url));
      if (!quiet) _showError(error.message);
    }
  }

  List<Message> _visible(List<Message> messages) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages
        .where(
          (message) => (message.content ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Thread.background,
      appBar: _buildAppBar(),
      body: StreamBuilder<List<Message>>(
        stream: _messages,
        builder: (context, snapshot) {
          final messages = _withPending(snapshot.data ?? const <Message>[]);
          _autoDownload(messages);

          return Column(
            children: <Widget>[
              Expanded(
                child: ThreadBackground(
                  child: _history(snapshot, _visible(messages), messages),
                ),
              ),
              MessageComposer(
                onSend: _send,
                replyingTo: _replyingTo,
                replyingToName:
                    _replyingTo == null ? null : _authorOf(_replyingTo!),
                replyWarning: _replyingTo == null
                    ? null
                    : _replyingTo!.whatsappMessageId == null
                        ? (_replyingTo!.hasFailed
                            ? 'This message never reached WhatsApp, so the '
                                'customer will see your reply without the '
                                'quote.'
                            : 'This message is still sending; the customer '
                                'will see your reply without the quote.')
                        : null,
                onCancelReply: () => setState(() => _replyingTo = null),
                windowOpen: _windowOpen(messages),
                onTemplates: _openTemplates,
                onVoiceNote: _sendVoiceNote,
                onRecorderProblem: _notify,
                onCreateQuickReply: _createQuickReply,
                onEditQuickReply: _editQuickReply,
                onDeleteQuickReply: (reply) => _shortcuts.delete(reply.id),
                canManageQuickReply: (reply) => reply.canBeManagedBy(
                  authUserId: widget.tenantContext.authUserId,
                  isAdmin:
                      widget.tenantContext.role == AppRole.admin ||
                      widget.tenantContext.role == AppRole.superAdmin,
                ),
                onSendShortcutMedia: _sendShortcutMedia,
                loadQuickReplies: () => _shortcuts.fetchAll(
                  tenantAdminId: widget.tenantContext.tenantAdminId,
                  authUserId: widget.tenantContext.authUserId,
                ),
                onAttach: (option) => unawaited(_onAttach(option)),
                onSchedule: _onSchedule,
                lastInboundAt: _lastInboundAt(messages),
                loadTemplates: _templates.fetchApproved,
                onBlocked: _onWindowBlocked,
                noticeHidden: _noticeHidden,
                onDismissNotice: () => setState(() => _noticeHidden = true),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Thread.composer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      iconTheme: const IconThemeData(color: Wa.icon),
      title: _searching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Thread.text, fontSize: 16),
              cursorColor: Wa.accent,
              decoration: const InputDecoration(
                hintText: 'Search in this conversation',
                hintStyle: TextStyle(color: Thread.meta, fontSize: 16),
                // The app theme fills every field by default, which would
                // draw a box across the app bar.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (value) => setState(() => _query = value),
            )
          : Row(
              children: <Widget>[
                // WhatsApp's header: a 40px avatar, the name at 16.5, and the
                // number right under it at 12.5. Tapping either opens the
                // contact, as it does there.
                ContactAvatar(chat: widget.chat, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _openContactInfo,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.chat.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Thread.text,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                        // The number is always the subtitle; the assignee
                        // moved into the menu, where it has room for a name.
                        if (widget.chat.shownPhone.isNotEmpty)
                          Text(
                            widget.chat.shownPhone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Thread.meta,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      actions: <Widget>[
        // WhatsApp's 📞 beside search: a WhatsApp voice call from the
        // business number, placed and carried inside the app (Meta's
        // Calling API; call-router does the signalling).
        if (widget.chat.normalisedPhone.isNotEmpty)
          IconButton(
            key: const ValueKey<String>('thread-call'),
            onPressed: _callCustomer,
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Call',
          ),
        IconButton(
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) {
              _searchController.clear();
              _query = '';
            }
          }),
          icon: Icon(_searching ? Icons.close : Icons.search),
          tooltip: _searching ? 'Close search' : 'Search',
        ),
        // Everything else lives behind the overflow. The pickers used to sit
        // out here as icons, but five actions left the name and number with
        // no room at all on a phone — and WhatsApp itself keeps the header to
        // avatar, name, number and one menu.
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert, color: Wa.icon),
          color: Wa.rowHover,
          onSelected: (value) {
            switch (value) {
              case 'labels':
                _openLabels();
              case 'categories':
                _openCategories();
              case 'convert_lead':
                _convertToLead();
            }
          },
          // Contact info opens by tapping the name in the header, templates
          // from the composer's + menu and the closed-window notice, and
          // assignment and the number from inside the contact sheet — so the
          // menu carries only what has nowhere else to live.
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _menuItem(
              'labels',
              Icons.sell_outlined,
              'Labels',
              count: _chatTags.labelIds.length,
            ),
            _menuItem(
              'categories',
              Icons.account_tree_outlined,
              'Categories',
              count: _chatTags.categoryIds.length,
            ),
            const PopupMenuDivider(),
            _menuItem('convert_lead', Icons.trending_up, 'Convert to Lead'),
          ],
        ),
      ],
    );
  }

  Future<void> _copyPhone() async {
    // What lands on the clipboard is the number as displayed — the ten
    // digits, not the stored 91-prefixed form.
    final phone = widget.chat.shownPhone;
    if (phone.isEmpty) {
      _showError('This chat has no phone number.');
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: phone));
    } catch (error) {
      // A browser can refuse the clipboard outright — saying so beats a
      // "Copied" that did not happen.
      _showError('Could not copy the number: $error');
      return;
    }
    // Only claimed once the write actually went through.
    _notify('Copied $phone');
  }

  Widget _history(
    AsyncSnapshot<List<Message>> snapshot,
    List<Message> visible,
    List<Message> all,
  ) {
    if (snapshot.hasError) {
      return _MessagesError(message: snapshot.error.toString());
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator(color: Wa.accent));
    }
    if (visible.isEmpty) {
      return _EmptyConversation(searching: _query.trim().isNotEmpty);
    }

    final byId = <String, Message>{
      ..._quotedExtra,
      for (final message in all) message.id: message,
    };
    _resolveMissingQuotes(visible, byId);
    final items = buildThreadItems(visible);

    // A "load earlier" row sits above the oldest message once a full first
    // page has come in, so the thread can be walked back; it disappears when
    // a page comes back short. Searching hides it — the search only covers
    // what is loaded and a partial answer would mislead.
    final showLoader = _query.trim().isEmpty &&
        _mayHaveOlder &&
        all.length >= MessagesRepository.livePageSize;
    final rowCount = items.length + (showLoader ? 1 : 0);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rowCount,
      itemBuilder: (context, index) {
        // reverse:true renders index 0 at the bottom; the loader is last.
        if (showLoader && index == rowCount - 1) {
          return _LoadEarlier(
            loading: _loadingOlder,
            onPressed: () => _loadOlder(all),
          );
        }
        final item = items[items.length - 1 - index];
        if (item is DateTime) return DayDivider(day: item);

        final message = item as Message;
        final quotedId = message.replyToMessageId;
        return MessageBubble(
          message: message,
          showTail: startsRun(items, items.length - 1 - index),
          avatar: message.isOutbound
              ? null
              : ContactAvatar(chat: widget.chat, radius: 20),
          repliedTo: quotedId == null ? null : byId[quotedId],
          repliedToName: quotedId == null
              ? null
              : (byId[quotedId]?.isOutbound ?? false)
              ? 'You'
              : widget.chat.displayName,
          onOpenAttachment: (attachment) =>
              _openAttachment(attachment, caption: message.body),
          onDownloadAttachment: _downloadAttachment,
          saveState: _saveStateOf(message),
          autoLoadMedia: message.attachment == null ||
              MediaPolicy.instance.autoLoads(message.attachment!.type),
          onLongPress: () => _openMessageActions(message),
          onCancelScheduled: message.isScheduled
              ? () => _cancelScheduled(message)
              : null,
        );
      },
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          searching
              ? 'No messages match that search.'
              : 'No messages in this conversation yet.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Thread.meta, fontSize: 14),
        ),
      ),
    );
  }
}

class _MessagesError extends StatelessWidget {
  const _MessagesError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 40, color: Wa.error),
            const SizedBox(height: 12),
            const Text(
              'Could not load messages',
              style: TextStyle(color: Thread.text, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Thread.meta, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row above the oldest loaded message that pages the thread back.
class _LoadEarlier extends StatelessWidget {
  const _LoadEarlier({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Wa.accent,
                ),
              )
            : TextButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.history, size: 18, color: Wa.accent),
                label: const Text(
                  'Load earlier messages',
                  style: TextStyle(color: Wa.accent, fontSize: 13),
                ),
              ),
      ),
    );
  }
}
