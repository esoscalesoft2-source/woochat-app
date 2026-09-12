import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/templates_repository.dart';
import '../../../theme/wa_colors.dart';

/// The Meta language codes the web dialog offers.
const List<(String code, String label)> kTemplateLanguages =
    <(String, String)>[
  ('en_US', 'English (US)'),
  ('en_GB', 'English (UK)'),
  ('en', 'English'),
  ('ta', 'Tamil'),
  ('hi', 'Hindi'),
  ('ml', 'Malayalam'),
  ('te', 'Telugu'),
  ('kn', 'Kannada'),
];

/// Meta's template categories.
const List<(String code, String label)> kTemplateCategories =
    <(String, String)>[
  ('MARKETING', 'Marketing'),
  ('UTILITY', 'Utility'),
  ('AUTHENTICATION', 'Authentication'),
];

/// Header media options, as Meta names them.
const List<(String code, String label)> kTemplateHeaders = <(String, String)>[
  ('NONE', 'None'),
  ('IMAGE', 'Image'),
  ('VIDEO', 'Video'),
  ('DOCUMENT', 'Document'),
];

/// Appends `{{n}}` for the next parameter at the caret (or the end).
///
/// Pure so the numbering can be tested without a widget: the placeholder is
/// always one past the count of parameters already in the draft.
(String text, int caret) insertPlaceholder(
  String text,
  TextSelection selection,
  int parameterCount,
) {
  final token = '{{${parameterCount + 1}}}';
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : start;
  return (text.replaceRange(start, end, token), start + token.length);
}

/// "Create Admin Template", as a sheet that slides up — the web app's dialog
/// field for field: name, language, category, parameters, header media, body.
///
/// Returns true once the template was submitted.
Future<bool?> showCreateTemplateSheet(
  BuildContext context, {
  required Future<List<SavedParameter>> Function() loadParameters,
  required Future<SavedParameter> Function(String name) saveParameter,
  required Future<void> Function(TemplateDraft draft) create,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CreateTemplateSheet(
      loadParameters: loadParameters,
      saveParameter: saveParameter,
      create: create,
    ),
  );
}

class _CreateTemplateSheet extends StatefulWidget {
  const _CreateTemplateSheet({
    required this.loadParameters,
    required this.saveParameter,
    required this.create,
  });

  final Future<List<SavedParameter>> Function() loadParameters;
  final Future<SavedParameter> Function(String name) saveParameter;
  final Future<void> Function(TemplateDraft draft) create;

  @override
  State<_CreateTemplateSheet> createState() => _CreateTemplateSheetState();
}

class _CreateTemplateSheetState extends State<_CreateTemplateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _body = TextEditingController();
  final _newParameter = TextEditingController();

  String _language = kTemplateLanguages.first.$1;
  String _category = kTemplateCategories.first.$1;
  String _header = kTemplateHeaders.first.$1;

  /// The team's reusable names, and the ones this draft actually uses in
  /// `{{1}}`, `{{2}}`… order.
  List<SavedParameter> _saved = const <SavedParameter>[];
  final List<String> _used = <String>[];

  bool _busy = false;
  bool _savingParameter = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.loadParameters().then((saved) {
      if (mounted) setState(() => _saved = saved);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    _newParameter.dispose();
    super.dispose();
  }

  /// Puts `{{n}}` into the body and records which name it stands for.
  void _useParameter(String name) {
    final (text, caret) =
        insertPlaceholder(_body.text, _body.selection, _used.length);
    _body
      ..text = text
      ..selection = TextSelection.collapsed(offset: caret);
    setState(() => _used.add(name));
  }

  Future<void> _addParameter() async {
    final name = _newParameter.text.trim();
    if (name.isEmpty || _savingParameter) return;

    setState(() => _savingParameter = true);
    try {
      final saved = await widget.saveParameter(name);
      if (!mounted) return;
      setState(() {
        _saved = <SavedParameter>[..._saved, saved];
        _newParameter.clear();
      });
    } on TemplateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _savingParameter = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.create(
        TemplateDraft(
          name: _name.text.trim(),
          language: _language,
          category: _category,
          bodyText: _body.text.trim(),
          headerFormat: _header,
          parameters: List<String>.unmodifiable(_used),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on TemplateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not create the template: $error');
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: <Widget>[
                const Text(
                  'Create Admin Template',
                  style: TextStyle(
                    color: Wa.title,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const _InfoBanner(
                  'This template will be submitted to Meta for every active '
                  'WhatsApp account in your admin panel.',
                ),
                const SizedBox(height: 16),
                const _Label('Template Name'),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: _decoration('e.g. order_confirmation'),
                  style: const TextStyle(color: Wa.title, fontSize: 14.5),
                  inputFormatters: <TextInputFormatter>[
                    // Lower-cased as typed, so a capital never has to be
                    // explained away by the validator.
                    TextInputFormatter.withFunction(
                      (_, next) => next.copyWith(text: next.text.toLowerCase()),
                    ),
                  ],
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Enter a template name';
                    if (!TemplateDraft.namePattern.hasMatch(text)) {
                      return 'Lowercase letters, numbers and underscores only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lowercase letters, numbers, and underscores only.',
                  style: TextStyle(color: Wa.secondaryText, fontSize: 11.5),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Dropdown(
                        label: 'Language',
                        value: _language,
                        options: kTemplateLanguages,
                        enabled: !_busy,
                        onChanged: (value) => setState(() => _language = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Dropdown(
                        label: 'Category',
                        value: _category,
                        options: kTemplateCategories,
                        enabled: !_busy,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('Parameters'),
                _ParametersBox(
                  saved: _saved,
                  used: _used,
                  controller: _newParameter,
                  saving: _savingParameter,
                  enabled: !_busy,
                  onUse: _useParameter,
                  onAdd: _addParameter,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap a parameter to add a variable like {{1}}, {{2}} to your '
                  'body text.',
                  style: TextStyle(color: Wa.secondaryText, fontSize: 11.5),
                ),
                const SizedBox(height: 16),
                const _Label('Header Media (optional)'),
                _Segmented(
                  value: _header,
                  options: kTemplateHeaders,
                  enabled: !_busy,
                  onChanged: (value) => setState(() => _header = value),
                ),
                const SizedBox(height: 16),
                const _Label('Body Text'),
                TextFormField(
                  controller: _body,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 8,
                  decoration: _decoration(
                    'Hello {{1}}, your order {{2}} has been confirmed!',
                  ),
                  style: const TextStyle(color: Wa.title, fontSize: 14.5),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter the message body'
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
                          'Create for My Users',
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

  static InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Wa.secondaryText, fontSize: 14),
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Wa.accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Wa.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: Wa.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Wa.title, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(label),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          dropdownColor: Wa.menu,
          iconEnabledColor: Wa.icon,
          style: const TextStyle(color: Wa.title, fontSize: 14),
          decoration: _CreateTemplateSheetState._decoration(''),
          items: <DropdownMenuItem<String>>[
            for (final (code, name) in options)
              DropdownMenuItem<String>(value: code, child: Text(name)),
          ],
          onChanged: enabled
              ? (next) {
                  if (next != null) onChanged(next);
                }
              : null,
        ),
      ],
    );
  }
}

/// The saved-parameter chips plus the field for adding a new one.
class _ParametersBox extends StatelessWidget {
  const _ParametersBox({
    required this.saved,
    required this.used,
    required this.controller,
    required this.saving,
    required this.enabled,
    required this.onUse,
    required this.onAdd,
  });

  final List<SavedParameter> saved;
  final List<String> used;
  final TextEditingController controller;
  final bool saving;
  final bool enabled;
  final ValueChanged<String> onUse;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.input,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Wa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Your saved parameters (reusable across templates — only your '
            'team sees these)',
            style: TextStyle(color: Wa.secondaryText, fontSize: 11.5),
          ),
          if (saved.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final parameter in saved)
                  ActionChip(
                    label: Text(parameter.name),
                    avatar: const Icon(Icons.add, size: 14, color: Wa.accent),
                    labelStyle: const TextStyle(color: Wa.title, fontSize: 12),
                    backgroundColor: Wa.header,
                    side: const BorderSide(color: Wa.border),
                    onPressed: enabled ? () => onUse(parameter.name) : null,
                  ),
              ],
            ),
          ],
          if (used.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              <String>[
                for (var i = 0; i < used.length; i++) '{{${i + 1}}} = ${used[i]}',
              ].join('   '),
              style: const TextStyle(color: Wa.accent, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled && !saving,
                  onSubmitted: (_) => onAdd(),
                  style: const TextStyle(color: Wa.title, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'e.g. OTP Code, Tracking ID',
                    hintStyle:
                        const TextStyle(color: Wa.secondaryText, fontSize: 13),
                    filled: true,
                    fillColor: Wa.header,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Wa.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Wa.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: enabled && !saving ? onAdd : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Wa.title,
                  side: const BorderSide(color: Wa.border),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: saving
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Wa.accent,
                        ),
                      )
                    : const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// None / Image / Video / Document, as a row of pills.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final (code, label) in options) ...<Widget>[
          Expanded(
            child: _Pill(
              label: label,
              selected: code == value,
              onTap: enabled ? () => onChanged(code) : null,
            ),
          ),
          if (code != options.last.$1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Wa.accent : Wa.input,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? Wa.accent : Wa.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Wa.onAccent : Wa.title,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
