import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/attachment_picker.dart';
import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';

/// The per-type upload caps the web app's New Shortcut dialog enforces.
const int kShortcutImageLimitBytes = 2 * 1024 * 1024;
const int kShortcutAudioLimitBytes = 1 * 1024 * 1024;
const int kShortcutVideoLimitBytes = 5 * 1024 * 1024;

/// The cap for one media kind, or null when there is none.
int? shortcutLimitFor(String type) => switch (type) {
      'image' => kShortcutImageLimitBytes,
      'audio' => kShortcutAudioLimitBytes,
      'video' => kShortcutVideoLimitBytes,
      _ => null,
    };

/// A shortcut word: letters, digits, underscores and dashes, no spaces — it
/// has to be typeable after a `/` in one go.
final RegExp kShortcutPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Drops any leading slashes and moves the caret back by as many characters,
/// so the selection never points past the shortened text — which is an
/// assertion failure inside the text input pipeline, not a quiet no-op.
TextEditingValue _stripLeadingSlash(
  TextEditingValue _,
  TextEditingValue next,
) {
  final stripped = next.text.replaceFirst(RegExp(r'^/+'), '');
  if (stripped.length == next.text.length) return next;

  final removed = next.text.length - stripped.length;
  int shift(int offset) => (offset - removed).clamp(0, stripped.length);

  return TextEditingValue(
    text: stripped,
    selection: TextSelection(
      baseOffset: shift(next.selection.baseOffset),
      extentOffset: shift(next.selection.extentOffset),
    ),
  );
}

/// "New quick reply", as a sheet that slides up from the `+` menu.
///
/// Pass [existing] to edit one instead of writing a new one: the fields open
/// filled in and the sheet says so throughout.
///
/// Returns the saved reply, or null if the sheet was dismissed.
Future<QuickReply?> showCreateQuickReplySheet(
  BuildContext context, {
  required Future<QuickReply> Function(
    String title,
    String message,
    List<QuickReplyMedia> media,
  ) save,
  Future<QuickReplyMedia?> Function(String kind)? addMedia,
  QuickReply? existing,
}) {
  return showModalBottomSheet<QuickReply>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CreateQuickReplySheet(
      save: save,
      addMedia: addMedia,
      existing: existing,
    ),
  );
}

class _CreateQuickReplySheet extends StatefulWidget {
  const _CreateQuickReplySheet({
    required this.save,
    required this.addMedia,
    required this.existing,
  });

  /// The reply being edited, or null when writing a new one.
  final QuickReply? existing;

  final Future<QuickReply> Function(
    String title,
    String message,
    List<QuickReplyMedia> media,
  ) save;

  /// Picks and uploads one file of [kind] — image, audio or video — and
  /// returns it. Without it the Media block is hidden and a message is
  /// required, as before.
  final Future<QuickReplyMedia?> Function(String kind)? addMedia;

  @override
  State<_CreateQuickReplySheet> createState() => _CreateQuickReplySheetState();
}

class _CreateQuickReplySheetState extends State<_CreateQuickReplySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _message =
      TextEditingController(text: widget.existing?.message ?? '');
  late final _media = <QuickReplyMedia>[...?widget.existing?.media];

  bool get _editing => widget.existing != null;

  bool _busy = false;

  /// True while a file is being picked and uploaded.
  bool _uploading = false;
  String? _error;

  bool get _canAddMedia => widget.addMedia != null;

  Future<void> _addMedia(String kind) async {
    if (_uploading || _busy) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final item = await widget.addMedia!(kind);
      if (item != null && mounted) setState(() => _media.add(item));
    } on AttachmentPickerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not add the file: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    // A reply needs something to insert: text, media, or both. The form
    // validator cannot see the media list, so the check lives here.
    if (_message.text.trim().isEmpty && _media.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Add a message and/or media.';
      });
      return;
    }

    try {
      final reply = await widget.save(
        _title.text.trim(),
        _message.text.trim(),
        List<QuickReplyMedia>.unmodifiable(_media),
      );
      if (mounted) Navigator.of(context).pop(reply);
    } on ShortcutException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the quick reply: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _editing ? 'Edit quick reply' : 'New quick reply',
                  style: const TextStyle(
                    color: Wa.title,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Type / in the message box to use it.',
                  style: TextStyle(color: Wa.secondaryText, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                const _Label('Shortcut'),
                TextFormField(
                  controller: _title,
                  enabled: !_busy,
                  // An edit opens on the filled-in form, not the keyboard.
                  autofocus: !_editing,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    // A leading slash is what people type from habit; the
                    // menu draws its own, so it is dropped rather than
                    // stored twice.
                    TextInputFormatter.withFunction(_stripLeadingSlash),
                  ],
                  decoration: _decoration('e.g. welcome', prefix: '/'),
                  style: const TextStyle(color: Wa.title, fontSize: 14.5),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Enter a shortcut word';
                    if (!kShortcutPattern.hasMatch(text)) {
                      return 'Letters, numbers, _ and - only — no spaces';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _Label(
                  _canAddMedia ? 'Message (optional if media is set)' : 'Message',
                ),
                TextFormField(
                  controller: _message,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    // Clears the "message and/or media" complaint as soon as
                    // the reason for it goes away.
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: _decoration(
                    'Type your quick reply message...',
                  ),
                  style: const TextStyle(color: Wa.title, fontSize: 14.5),
                  validator: (value) {
                    if (_canAddMedia) return null;
                    return (value?.trim().isEmpty ?? true)
                        ? 'Enter the reply text'
                        : null;
                  },
                ),
                if (_canAddMedia) ...<Widget>[
                  const SizedBox(height: 16),
                  _MediaBox(
                    media: _media,
                    uploading: _uploading,
                    enabled: !_busy,
                    onAdd: _addMedia,
                    onRemove: (index) => setState(() => _media.removeAt(index)),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Wa.error, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Wa.onAccent,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Wa.onAccent,
                          ),
                        )
                      : Text(
                          _editing
                              ? 'Save changes'
                              : (_canAddMedia ? 'Create' : 'Save quick reply'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static InputDecoration _decoration(String hint, {String? prefix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Wa.secondaryText, fontSize: 14),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: Wa.accent, fontSize: 14.5),
        filled: true,
        fillColor: Wa.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.error),
        ),
      );
}

/// The "Media (optional)" block: the three add buttons, the caps the web app
/// spells out, and whatever has been attached so far.
class _MediaBox extends StatelessWidget {
  const _MediaBox({
    required this.media,
    required this.uploading,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<QuickReplyMedia> media;
  final bool uploading;
  final bool enabled;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final on = enabled && !uploading;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.input,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Wa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Media (optional)',
            style: TextStyle(color: Wa.secondaryText, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _AddButton(
                icon: Icons.file_upload_outlined,
                label: 'Add images',
                onPressed: on ? () => onAdd('image') : null,
              ),
              _AddButton(
                icon: Icons.mic_none,
                label: 'Add audio',
                onPressed: on ? () => onAdd('audio') : null,
              ),
              _AddButton(
                icon: Icons.videocam_outlined,
                label: 'Add video',
                onPressed: on ? () => onAdd('video') : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            uploading
                ? 'Uploading…'
                : 'Images \u2264 2MB · audio \u2264 1MB · video \u2264 5MB',
            style: const TextStyle(color: Wa.secondaryText, fontSize: 11.5),
          ),
          for (var index = 0; index < media.length; index++)
            _MediaRow(
              item: media[index],
              onRemove: enabled ? () => onRemove(index) : null,
            ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Wa.background,
        foregroundColor: Wa.title,
        disabledBackgroundColor: Wa.background,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13.5)),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.item, required this.onRemove});

  final QuickReplyMedia item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      'image' => Icons.image_outlined,
      'video' => Icons.videocam_outlined,
      'audio' => Icons.music_note_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: Wa.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Wa.title, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove ${item.name}',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: Wa.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Wa.title,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
