import 'package:flutter/material.dart';

import '../../../models/chat_filters.dart';
import '../../../theme/wa_colors.dart';

/// What the sheet was left holding: the notes now on the contact, and any
/// note written while it was open.
class ChatNotesResult {
  const ChatNotesResult({required this.attached, this.created});

  final List<Note> attached;
  final Note? created;
}

/// The Notes entry on a chat row: the workspace's note library with the ones
/// on this customer ticked, a search box, and "New note…" at the bottom —
/// the same shape as the web row's Notes submenu.
///
/// Notes hang off the CONTACT record, so a chat whose number has no contact
/// yet is told so rather than shown a list it cannot use.
///
/// Returns what is attached when the sheet closes, or null when nothing
/// could be changed.
Future<ChatNotesResult?> showChatNotesSheet(
  BuildContext context, {
  required String chatName,
  required String? contactId,
  required List<Note> library,
  required List<Note> attached,
  required Future<bool> Function(Note note, bool attach) onToggle,
  required Future<Note?> Function() onCreate,
}) {
  return showModalBottomSheet<ChatNotesResult>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _ChatNotesSheet(
      chatName: chatName,
      contactId: contactId,
      library: library,
      attached: attached,
      onToggle: onToggle,
      onCreate: onCreate,
    ),
  );
}

class _ChatNotesSheet extends StatefulWidget {
  const _ChatNotesSheet({
    required this.chatName,
    required this.contactId,
    required this.library,
    required this.attached,
    required this.onToggle,
    required this.onCreate,
  });

  final String chatName;
  final String? contactId;
  final List<Note> library;
  final List<Note> attached;
  final Future<bool> Function(Note note, bool attach) onToggle;
  final Future<Note?> Function() onCreate;

  @override
  State<_ChatNotesSheet> createState() => _ChatNotesSheetState();
}

class _ChatNotesSheetState extends State<_ChatNotesSheet> {
  late final List<Note> _library = <Note>[...widget.library];
  late final Map<String, Note> _attached = <String, Note>{
    for (final note in widget.attached) note.id: note,
  };
  final _search = TextEditingController();
  String? _busyId;
  Note? _created;

  /// The web submenu caps the list at forty so it stays a menu, not a page.
  static const int _maxShown = 40;

  bool get _hasContact => widget.contactId != null;

  List<Note> get _visible {
    final query = _search.text.trim().toLowerCase();
    Iterable<Note> list = _library;
    if (query.isNotEmpty) {
      list = list.where((note) =>
          (note.text ?? '').toLowerCase().contains(query) ||
          note.tags.any((tag) => tag.toLowerCase().contains(query)));
    }
    return list.take(_maxShown).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(Note note) async {
    if (_busyId != null || !_hasContact) return;
    final attach = !_attached.containsKey(note.id);
    setState(() => _busyId = note.id);

    final ok = await widget.onToggle(note, attach);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (ok) {
        if (attach) {
          _attached[note.id] = note;
        } else {
          _attached.remove(note.id);
        }
      }
    });
  }

  Future<void> _create() async {
    final note = await widget.onCreate();
    if (note == null || !mounted) return;
    setState(() {
      _created = note;
      _library.insert(0, note);
      // A note written from a chat is linked to it on the way in.
      if (_hasContact) _attached[note.id] = note;
    });
  }

  void _close() {
    Navigator.of(context).pop(
      ChatNotesResult(
        attached: _sortedAttached(),
        created: _created,
      ),
    );
  }

  List<Note> _sortedAttached() => _attached.values.toList()
    ..sort((a, b) {
      final aAt = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bAt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bAt.compareTo(aAt);
    });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Notes · ${widget.chatName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Wa.title,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!_hasContact)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      'Save this number as a Contact to attach notes. Open '
                      'Contacts and add this phone number.',
                      style: TextStyle(color: Wa.secondaryText, fontSize: 13),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      key: const ValueKey<String>('notes-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Wa.title, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search notes…',
                        hintStyle: const TextStyle(color: Wa.secondaryText),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: Wa.input,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 1, color: Wa.divider),
                if (_hasContact)
                  Flexible(
                    child: _visible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
                            child: Text(
                              'No notes match.',
                              style: TextStyle(
                                color: Wa.secondaryText,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _visible.length,
                            itemBuilder: (context, index) {
                              final note = _visible[index];
                              final on = _attached.containsKey(note.id);
                              return ListTile(
                                onTap: () => _toggle(note),
                                dense: true,
                                leading: _busyId == note.id
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Wa.accent,
                                        ),
                                      )
                                    : Icon(
                                        on
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 20,
                                        color: on ? Wa.accent : Wa.icon,
                                      ),
                                title: Text(
                                  (note.text ?? '').trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Wa.title,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: note.tags.isEmpty
                                    ? null
                                    : Text(
                                        note.tags.join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Wa.secondaryText,
                                          fontSize: 11.5,
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                const Divider(height: 1, color: Wa.divider),
                ListTile(
                  onTap: _create,
                  leading: const Icon(
                    Icons.sticky_note_2_outlined,
                    color: Wa.accent,
                    size: 20,
                  ),
                  title: const Text(
                    'New note…',
                    style: TextStyle(color: Wa.accent, fontSize: 14.5),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small editor for a new note: the text and optional tags.
///
/// Returns (text, tags) on save, or null when dismissed.
Future<(String, List<String>)?> showNewNoteSheet(
  BuildContext context, {
  List<String> suggestedTags = const <String>[],
}) {
  return showModalBottomSheet<(String, List<String>)>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _NewNoteSheet(suggestedTags: suggestedTags),
  );
}

class _NewNoteSheet extends StatefulWidget {
  const _NewNoteSheet({required this.suggestedTags});

  final List<String> suggestedTags;

  @override
  State<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends State<_NewNoteSheet> {
  final _text = TextEditingController();
  final _tags = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();

  void _addTag(String tag) {
    final current = _parsedTags;
    if (current.contains(tag)) return;
    _tags.text = <String>[...current, tag].join(', ');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _text.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'New note',
                style: TextStyle(
                  color: Wa.title,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('note-text'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Wa.title, fontSize: 14.5),
                decoration: _decoration('Write the note…'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>('note-tags'),
                controller: _tags,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Wa.title, fontSize: 14),
                decoration: _decoration('Tags, comma separated (optional)'),
              ),
              if (widget.suggestedTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final tag in widget.suggestedTags.take(12))
                      ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _addTag(tag),
                        backgroundColor: Wa.input,
                        side: BorderSide.none,
                        labelStyle: const TextStyle(color: Wa.title),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: canSave
                    ? () => Navigator.of(context)
                        .pop((_text.text.trim(), _parsedTags))
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Wa.accent,
                  foregroundColor: Wa.onAccent,
                  disabledBackgroundColor: Wa.disabled,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Save note',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Wa.secondaryText, fontSize: 14),
        filled: true,
        fillColor: Wa.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      );
}
