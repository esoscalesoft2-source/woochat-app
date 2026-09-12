import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../data/attachments_repository.dart';
import '../../data/chat_assignment_repository.dart';
import '../../data/chat_tags_repository.dart';
import '../../data/leads_repository.dart';
import '../../data/messages_repository.dart';
import '../../data/shortcuts_repository.dart';
import '../../data/templates_repository.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chats/widgets/contact_avatar.dart';
import 'thread_items.dart';
import 'widgets/assign_chat_sheet.dart';
import 'widgets/attach_menu.dart';
import 'widgets/chat_tags_sheet.dart';
import 'widgets/contact_info_sheet.dart';
import 'widgets/create_quick_reply_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';
import 'widgets/schedule_message_sheet.dart';
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
  final _tags = const ChatTagsRepository();
  final _shortcuts = const ShortcutsRepository();
  final _leads = const LeadsRepository();
  final _searchController = TextEditingController();

  /// The chat's labels and categories. Loaded once the thread opens; the
  /// header buttons tint themselves from it.
  ChatTags _chatTags = ChatTags.empty;
  bool _tagsLoaded = false;

  /// `chats.assigned_to` for this chat, and the people it can point at.
  final _assignments = const ChatAssignmentRepository();
  String? _assignedTo;
  List<TeamMember> _members = const <TeamMember>[];
  bool _assignmentLoaded = false;

  late final Stream<List<Message>> _messages =
      _repository.watchMessages(widget.chat.id);

  bool _searching = false;
  String _query = '';

  /// The expired-window strip can be put away, but it comes straight back on
  /// the next thing the closed window refuses — which is the moment its
  /// explanation is wanted.
  bool _noticeHidden = false;

  void _onWindowBlocked() {
    setState(() => _noticeHidden = false);
    _notify(kWindowClosedMessage);
  }

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadAssignment();
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
    _searchController.dispose();
    super.dispose();
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
        write: (id, applied) =>
            _tags.setLabel(widget.chat.id, id, applied: applied),
        commit: (ids) => _chatTags = _chatTags.copyWith(labelIds: ids),
      );

  Future<void> _openCategories() => _openTagPicker(
        title: 'Categories',
        emptyMessage: 'No categories exist in this workspace yet.',
        options: <TagOption>[
          for (final category in _chatTags.categories)
            TagOption(
              id: category.id,
              name: category.name,
              color: category.color,
            ),
        ],
        selected: _chatTags.categoryIds,
        write: (id, applied) =>
            _tags.setCategory(widget.chat.id, id, applied: applied),
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

  Future<void> _openContactInfo() async {
    await showContactInfoSheet(
      context,
      chat: widget.chat,
      assignedName: _assignedName,
      labels: <String>[
        for (final label in _chatTags.labels)
          if (_chatTags.labelIds.contains(label.id)) label.name,
      ],
      categories: <String>[
        for (final category in _chatTags.categories)
          if (_chatTags.categoryIds.contains(category.id)) category.name,
      ],
      onCopyNumber: () {
        Navigator.of(context).pop();
        _copyPhone();
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

  Future<bool> _send(String text) async {
    try {
      await _repository.sendTextMessage(
        chatId: widget.chat.id,
        // The row is authored by whoever is signed in; the edge function needs
        // the chat's owner separately to resolve the sending number.
        senderUserId: widget.tenantContext.authUserId,
        chatOwnerUserId: widget.chat.userId,
        content: text,
        contactPhone: widget.chat.contactPhone,
      );
      return true;
    } on MessageSendException catch (error) {
      // The row was inserted and is now marked failed, so it is visible in the
      // thread — clearing the composer loses nothing.
      _showError(error.message);
      return true;
    } catch (error) {
      // The insert itself failed, so nothing was persisted anywhere. Keep the
      // typed text so the user can retry instead of losing it.
      _showError('Could not send the message: $error');
      return false;
    }
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
    await showTemplatesSheet(
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
  }

  /// Uploads a finished recording into the existing bucket, then sends it as
  /// an ordinary outbound message carrying an audio attachment marker.
  Future<bool> _sendVoiceNote(VoiceClip clip) async {
    try {
      final url = await _attachments.upload(
        authUserId: widget.tenantContext.authUserId,
        chatId: widget.chat.id,
        fileName: clip.fileName,
        bytes: clip.bytes,
        contentType: clip.contentType,
      );

      await _repository.sendTextMessage(
        chatId: widget.chat.id,
        senderUserId: widget.tenantContext.authUserId,
        chatOwnerUserId: widget.chat.userId,
        // The marker is what the row stores so the thread can draw a player;
        // WhatsApp gets the file through the media keys instead.
        content: Message.attachmentMarker(
          type: 'audio',
          name: clip.fileName,
          url: url,
        ),
        contactPhone: widget.chat.contactPhone,
        media: OutboundMedia(
          url: url,
          type: 'audio',
          mimeType: clip.contentType,
          fileName: clip.fileName,
        ),
      );
      return true;
    } on AttachmentUploadException catch (error) {
      _showError(error.message);
      return false;
    } on MessageSendException catch (error) {
      // The row exists and is marked failed, so the note is visible in the
      // thread with its reason.
      _showError(error.message);
      return true;
    } catch (error) {
      _showError('Could not send the voice note: $error');
      return false;
    }
  }

  /// Everything on the attach menu except Template Message, which already has
  /// a real destination.
  void _onAttach(AttachOption option) {
    final what = switch (option) {
      AttachOption.document => 'Documents',
      AttachOption.photos => 'Photos and videos',
      AttachOption.audio => 'Audio files',
      AttachOption.camera => 'The camera',
      AttachOption.contact => 'Contact cards',
      AttachOption.template => 'Templates',
      AttachOption.quickReply => 'Quick replies',
    };
    _notify(
      '$what need a file picker and an upload into the chat-attachments '
      'bucket - not wired up yet.',
    );
  }

  /// The + menu's Quick Replies: a sheet that saves a new `/shortcut` to the
  /// existing `shortcuts` table, then hands it back so the composer can offer
  /// it straight away.
  Future<QuickReply?> _createQuickReply() async {
    final reply = await showCreateQuickReplySheet(
      context,
      save: (title, message) => _shortcuts.create(
        userId: widget.tenantContext.authUserId,
        title: title,
        message: message,
      ),
    );
    if (reply != null) _notify('Saved /${reply.title}. Type / to use it.');
    return reply;
  }

  void _onSchedule(ScheduledSend scheduled) {
    final when = DateFormat('d MMM yyyy, h:mm a').format(scheduled.at);
    _notify(
      'Picked $when. Writing the scheduled message is not wired up yet - the '
      'Schedules filter already reads them.',
    );
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

  Future<void> _openAttachment(MessageAttachment attachment) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showError('Could not open ${attachment.name}.');
  }

  List<Message> _visible(List<Message> messages) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages
        .where((message) =>
            (message.content ?? '').toLowerCase().contains(query))
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
          final messages = snapshot.data ?? const <Message>[];

          return Column(
            children: <Widget>[
              Expanded(
                child: ThreadBackground(
                  child: _history(snapshot, _visible(messages), messages),
                ),
              ),
              MessageComposer(
                onSend: _send,
                windowOpen: _windowOpen(messages),
                onTemplates: _openTemplates,
                onVoiceNote: _sendVoiceNote,
                onRecorderProblem: _notify,
                onCreateQuickReply: _createQuickReply,
                loadQuickReplies: () => _shortcuts.fetchAll(
                      tenantAdminId: widget.tenantContext.tenantAdminId,
                      authUserId: widget.tenantContext.authUserId,
                    ),
                onAttach: _onAttach,
                onSchedule: _onSchedule,
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
                        if (widget.chat.contactPhone != null)
                          Text(
                            widget.chat.contactPhone!,
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
              case 'contact_info':
                _openContactInfo();
              case 'labels':
                _openLabels();
              case 'categories':
                _openCategories();
              case 'assign':
                _openAssign();
              case 'templates':
                _openTemplates();
              case 'convert_lead':
                _convertToLead();
              case 'copy_phone':
                _copyPhone();
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _menuItem('contact_info', Icons.info_outline, 'Contact info'),
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
            _menuItem(
              'assign',
              Icons.person_outline,
              _assignedName == null ? 'Assign' : 'Assigned: $_assignedName',
            ),
            const PopupMenuDivider(),
            _menuItem('templates', Icons.description_outlined, 'Templates'),
            _menuItem('convert_lead', Icons.trending_up, 'Convert to Lead'),
            _menuItem('copy_phone', Icons.copy_outlined, 'Copy number'),
          ],
        ),
      ],
    );
  }

  void _copyPhone() {
    final phone = widget.chat.contactPhone;
    if (phone == null || phone.isEmpty) {
      _showError('This chat has no phone number.');
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Copied $phone'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    final byId = <String, Message>{for (final message in all) message.id: message};
    final items = buildThreadItems(visible);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        // reverse:true renders index 0 at the bottom.
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
          onOpenAttachment: _openAttachment,
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

