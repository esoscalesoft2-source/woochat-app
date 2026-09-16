import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../models/message.dart';
import '../../../theme/wa_colors.dart';
import '../../chats/widgets/contact_avatar.dart';

/// One chat per customer, the most recently active one for each number.
///
/// The `chats` table holds duplicate rows for a customer — the same number
/// with and without its country code, or created twice from New Chat — and
/// a forward picked from a list of duplicates lands in whichever row was
/// tapped, which is not the thread the agent then looks at. Collapsing them
/// here means "gokila" is offered once, and the message goes where the
/// conversation actually is.
List<Chat> onePerCustomer(Iterable<Chat> chats) {
  final byCustomer = <String, Chat>{};
  for (final chat in chats) {
    final key = chat.canonicalPhone.isEmpty ? chat.id : chat.canonicalPhone;
    final current = byCustomer[key];
    if (current == null || _newer(chat, current)) byCustomer[key] = chat;
  }
  return byCustomer.values.toList();
}

bool _newer(Chat a, Chat b) {
  final aAt = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
  final bAt = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
  return aAt > bAt;
}

/// What the forward screen hands back: the chats picked, and the extra
/// message typed under the preview (empty when none).
class ForwardChoice {
  const ForwardChoice({required this.chats, required this.note});

  final List<Chat> chats;
  final String note;
}

/// WhatsApp's "Forward message to" screen: a search box, the chats with a
/// checkbox each, and once something is ticked a bar along the bottom with a
/// preview of what is being forwarded, an "Add a message…" box, the names
/// picked so far, and the send button.
///
/// Returns the choice, or null when dismissed.
Future<ForwardChoice?> showForwardSheet(
  BuildContext context, {
  required Message message,
  required Future<List<Chat>> Function() loadChats,
  required String Function(Chat chat) nameOf,
  required String? Function(Chat chat) photoOf,
  Chat? exclude,
}) {
  return Navigator.of(context).push<ForwardChoice>(
    MaterialPageRoute<ForwardChoice>(
      fullscreenDialog: true,
      builder: (context) => _ForwardScreen(
        message: message,
        loadChats: loadChats,
        nameOf: nameOf,
        photoOf: photoOf,
        exclude: exclude,
      ),
    ),
  );
}

class _ForwardScreen extends StatefulWidget {
  const _ForwardScreen({
    required this.message,
    required this.loadChats,
    required this.nameOf,
    required this.photoOf,
    required this.exclude,
  });

  /// What is being forwarded — previewed in the bottom bar.
  final Message message;
  final Future<List<Chat>> Function() loadChats;
  final String Function(Chat chat) nameOf;
  final String? Function(Chat chat) photoOf;

  /// The chat the message is already in. Every row for that customer is
  /// left out — forwarding to them is a resend, whichever row it landed in.
  final Chat? exclude;

  @override
  State<_ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<_ForwardScreen> {
  late final Future<List<Chat>> _future =
      widget.loadChats().then(_candidates);
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _picked = <String, Chat>{};

  /// WhatsApp caps a forward at five chats, and so does the web app's
  /// dialog — enough to share a photo, not enough to broadcast.
  static const int _maxTargets = 5;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.of(context).pop(
      ForwardChoice(
        chats: _picked.values.toList(),
        note: _note.text.trim(),
      ),
    );
  }

  /// One row per customer, minus the current one, most recent first.
  List<Chat> _candidates(List<Chat> all) {
    final current = widget.exclude;
    final merged = onePerCustomer(all).where((chat) {
      if (current == null) return true;
      if (chat.id == current.id) return false;
      return current.canonicalPhone.isEmpty ||
          chat.canonicalPhone != current.canonicalPhone;
    }).toList()
      ..sort((a, b) => _newer(a, b) ? -1 : (_newer(b, a) ? 1 : 0));
    return merged;
  }

  List<Chat> _visible(List<Chat> all) {
    final query = _search.text.trim().toLowerCase();
    // Typing a number searches numbers; typing words searches names. A
    // lone digit inside a word ("chat 3") must not match every phone.
    final digits = Chat.normalisePhone(query);
    final numeric = digits.isNotEmpty && !RegExp(r'[a-z]').hasMatch(query);
    return <Chat>[
      for (final chat in all)
        if ((query.isEmpty ||
                widget.nameOf(chat).toLowerCase().contains(query) ||
                (numeric && chat.normalisedPhone.contains(digits))))
          chat,
    ];
  }

  void _toggle(Chat chat) {
    setState(() {
      if (_picked.remove(chat.id) == null) {
        if (_picked.length >= _maxTargets) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('You can forward to up to $_maxTargets chats.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          return;
        }
        _picked[chat.id] = chat;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.background,
      appBar: AppBar(
        backgroundColor: Wa.header,
        foregroundColor: Wa.title,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Forward message to'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              key: const ValueKey<String>('forward-search'),
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Wa.title, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search name or number',
                hintStyle: const TextStyle(color: Wa.secondaryText),
                prefixIcon: const Icon(Icons.search, color: Wa.icon),
                isDense: true,
                filled: true,
                fillColor: Wa.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Wa.accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : _ForwardBar(
              message: widget.message,
              note: _note,
              recipients: _picked.values.map(widget.nameOf).toList(),
              onSend: _send,
            ),
      body: FutureBuilder<List<Chat>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Could not load chats.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Wa.secondaryText),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Wa.accent),
            );
          }

          final chats = _visible(snapshot.data!);
          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No chats match.',
                style: TextStyle(color: Wa.secondaryText),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: chats.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Recent chats',
                    style: TextStyle(color: Wa.secondaryText, fontSize: 14),
                  ),
                );
              }
              final chat = chats[index - 1];
              final on = _picked.containsKey(chat.id);
              return ListTile(
                onTap: () => _toggle(chat),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Checkbox(
                      value: on,
                      onChanged: (_) => _toggle(chat),
                      activeColor: Wa.accent,
                      checkColor: Wa.onAccent,
                      side: const BorderSide(color: Wa.outline, width: 1.5),
                    ),
                    ContactAvatar(
                      chat: chat,
                      radius: 22,
                      photoUrl: widget.photoOf(chat),
                    ),
                  ],
                ),
                title: Text(
                  widget.nameOf(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Wa.title, fontSize: 16),
                ),
                subtitle: Text(
                  chat.shownPhone,
                  style: const TextStyle(color: Wa.secondaryText, fontSize: 13),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The bar that appears along the bottom once a chat is ticked: a thumbnail
/// or line for what is being forwarded, the optional extra message, the
/// names picked, and the send button.
class _ForwardBar extends StatelessWidget {
  const _ForwardBar({
    required this.message,
    required this.note,
    required this.recipients,
    required this.onSend,
  });

  final Message message;
  final TextEditingController note;
  final List<String> recipients;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          key: const ValueKey<String>('forward-bar'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: const BoxDecoration(
            color: Wa.header,
            border: Border(top: BorderSide(color: Wa.divider, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Preview(message: message),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('forward-note'),
                      controller: note,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Wa.title, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Add a message…',
                        hintStyle: const TextStyle(color: Wa.secondaryText),
                        filled: true,
                        fillColor: Wa.input,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      recipients.join(', '),
                      key: const ValueKey<String>('forward-recipients'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Wa.title, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey<String>('forward-send'),
                      onPressed: onSend,
                      style: FilledButton.styleFrom(
                        backgroundColor: Wa.accent,
                        foregroundColor: Wa.onAccent,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send, size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The forwarded message, as a thumbnail for a picture or a short card for
/// anything else.
class _Preview extends StatelessWidget {
  const _Preview({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    if (attachment != null && attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          attachment.url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _PreviewCard(
            icon: Icons.image_outlined,
            label: 'Photo',
          ),
        ),
      );
    }
    if (attachment != null) {
      final (IconData icon, String label) = switch (attachment.type) {
        'video' => (Icons.videocam_outlined, 'Video'),
        'audio' => (Icons.mic_none, 'Audio'),
        _ => (Icons.insert_drive_file_outlined, attachment.name),
      };
      return _PreviewCard(icon: icon, label: label);
    }
    return _PreviewCard(icon: Icons.chat_bubble_outline, label: message.body);
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Wa.input,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Wa.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 22, color: Wa.accent),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Wa.secondaryText, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
