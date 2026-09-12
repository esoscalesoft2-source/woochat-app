import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';

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
/// Returns the saved reply, or null if the sheet was dismissed.
Future<QuickReply?> showCreateQuickReplySheet(
  BuildContext context, {
  required Future<QuickReply> Function(String title, String message) save,
}) {
  return showModalBottomSheet<QuickReply>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CreateQuickReplySheet(save: save),
  );
}

class _CreateQuickReplySheet extends StatefulWidget {
  const _CreateQuickReplySheet({required this.save});

  final Future<QuickReply> Function(String title, String message) save;

  @override
  State<_CreateQuickReplySheet> createState() => _CreateQuickReplySheetState();
}

class _CreateQuickReplySheetState extends State<_CreateQuickReplySheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _message = TextEditingController();

  bool _busy = false;
  String? _error;

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

    try {
      final reply = await widget.save(_title.text.trim(), _message.text.trim());
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
                const Text(
                  'New quick reply',
                  style: TextStyle(
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
                  autofocus: true,
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
                const _Label('Message'),
                TextFormField(
                  controller: _message,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _decoration(
                    'Hi! Welcome to Vicky\'s TRX. How can we help you today?',
                  ),
                  style: const TextStyle(color: Wa.title, fontSize: 14.5),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter the reply text'
                      : null,
                ),
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
                      : const Text(
                          'Save quick reply',
                          style: TextStyle(fontWeight: FontWeight.w600),
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
