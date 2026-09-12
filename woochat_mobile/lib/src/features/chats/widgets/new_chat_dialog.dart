import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/chats_repository.dart';
import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';

/// Colours for the New Chat modal, matching the web app's dialog.
class _T {
  const _T._();
  // The mockup's token names, resolved onto the app-wide WhatsApp palette.
  static const Color surface = Wa.menu;
  static const Color field = Wa.input;
  static const Color border = Wa.border;
  static const Color title = Wa.title;
  static const Color label = Wa.title;
  static const Color placeholder = Wa.secondaryText;
  static const Color icon = Wa.icon;
  static const Color button = Wa.accent;
  static const Color onButton = Colors.white;
  static const Color error = Wa.error;
}

/// Asks for a contact, then returns the conversation to open.
///
/// Creating a chat writes a row to `chats` and nothing else — no WhatsApp API
/// call is made, so this cannot affect the connected WhatsApp account.
/// Because the new row has no inbound message, the composer will correctly
/// treat the 24-hour customer window as closed.
Future<Chat?> showNewChatDialog(
  BuildContext context, {
  required String ownerId,
}) {
  return showDialog<Chat>(
    context: context,
    builder: (context) => _NewChatDialog(ownerId: ownerId),
  );
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog({required this.ownerId});

  final String ownerId;

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _repository = const ChatsRepository();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
      // Look for an existing conversation first so the same contact never
      // ends up with two rows.
      final existing = await _repository.findChatByPhone(
        ownerId: widget.ownerId,
        phone: _phone.text,
      );

      final chat = existing ??
          await _repository.createChat(
            ownerId: widget.ownerId,
            contactName: _name.text,
            contactPhone: _phone.text,
          );

      if (!mounted) return;
      if (existing != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content:
                  Text('Opening the existing chat with ${chat.displayName}.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      Navigator.of(context).pop(chat);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not start the chat: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _T.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _T.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'New Chat',
                        style: TextStyle(
                          color: _T.title,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      color: _T.icon,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _FieldLabel('Contact Name'),
                const SizedBox(height: 8),
                _field(
                  controller: _name,
                  hint: 'John Doe',
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter the contact name'
                      : null,
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Phone Number'),
                const SizedBox(height: 8),
                _field(
                  controller: _phone,
                  hint: '+91 9876543210',
                  keyboardType: TextInputType.phone,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    final digits = Chat.normalisePhone(value);
                    if (digits.isEmpty) return 'Enter the phone number';
                    if (digits.length < 8) return 'Enter a valid number';
                    return null;
                  },
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: _T.error, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _T.button,
                      foregroundColor: _T.onButton,
                      disabledBackgroundColor:
                          _T.button.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _T.onButton,
                            ),
                          )
                        : const Text(
                            'Start Chat',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    void Function(String)? onFieldSubmitted,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color),
        );

    return TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onFieldSubmitted: onFieldSubmitted,
      autocorrect: false,
      style: const TextStyle(color: _T.label, fontSize: 15),
      cursorColor: _T.button,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _T.placeholder, fontSize: 15),
        filled: true,
        fillColor: _T.field,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border(_T.border),
        enabledBorder: border(_T.border),
        disabledBorder: border(_T.border),
        focusedBorder: border(_T.button),
        errorBorder: border(_T.error),
        focusedErrorBorder: border(_T.error),
        errorStyle: const TextStyle(color: _T.error, fontSize: 12),
      ),
      validator: validator,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _T.label,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
