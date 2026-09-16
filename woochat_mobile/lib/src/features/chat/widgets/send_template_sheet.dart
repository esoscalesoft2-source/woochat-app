import 'package:flutter/material.dart';

import '../../../data/templates_repository.dart';
import '../../../theme/wa_colors.dart';

/// Fills in a template's `{{n}}` values and sends it.
///
/// One field per placeholder, a live preview of what the customer will read,
/// and Send stays disabled until every value is in — the same shape as the
/// web app's template dialog. Returns the values on Send, null on dismiss.
Future<Map<int, String>?> showSendTemplateSheet(
  BuildContext context, {
  required MessageTemplate template,
  required String chatName,
}) {
  return showModalBottomSheet<Map<int, String>>(
    context: context,
    backgroundColor: Thread.composer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _SendTemplateSheet(
      template: template,
      chatName: chatName,
    ),
  );
}

class _SendTemplateSheet extends StatefulWidget {
  const _SendTemplateSheet({required this.template, required this.chatName});

  final MessageTemplate template;
  final String chatName;

  @override
  State<_SendTemplateSheet> createState() => _SendTemplateSheetState();
}

class _SendTemplateSheetState extends State<_SendTemplateSheet> {
  late final List<int> _numbers = widget.template.parameterNumbers;
  late final Map<int, TextEditingController> _controllers = <int, TextEditingController>{
    for (final n in _numbers) n: TextEditingController(),
  };

  Map<int, String> get _values => <int, String>{
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      };

  bool get _complete => _values.values.every((value) => value.isNotEmpty);

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final headerUrl = template.headerExampleUrl?.trim();
    final hasImageHeader =
        template.headerMediaType == 'image' && (headerUrl?.isNotEmpty ?? false);

    return SafeArea(
      top: false,
      child: Padding(
        // Keep the fields above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  template.name,
                  style: const TextStyle(
                    color: Thread.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Sending to ${widget.chatName}'
                  '${template.language == null ? '' : ' · ${template.language}'}',
                  style: const TextStyle(color: Thread.meta, fontSize: 12),
                ),
              ),
              const Divider(height: 1, color: Wa.divider),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: <Widget>[
                    if (_numbers.isNotEmpty) ...<Widget>[
                      const Text(
                        'Fill in the values',
                        style: TextStyle(color: Thread.meta, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      for (final n in _numbers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            key: ValueKey<String>('template-param-$n'),
                            controller: _controllers[n],
                            autofocus: n == _numbers.first,
                            textInputAction: n == _numbers.last
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(color: Thread.text),
                            decoration: InputDecoration(
                              labelText: '{{$n}}',
                              labelStyle: const TextStyle(color: Thread.meta),
                              filled: true,
                              fillColor: Thread.input,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                    const Text(
                      'Preview',
                      style: TextStyle(color: Thread.meta, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Thread.outbound,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (hasImageHeader)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  headerUrl!,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            )
                          else if (template.headerMediaType != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '📎 ${template.headerFormat!.toUpperCase()} header',
                                style: const TextStyle(
                                  color: Thread.meta,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Text(
                            template.render(_values),
                            style: const TextStyle(
                              color: Thread.text,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _complete
                      ? () => Navigator.of(context).pop(_values)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Wa.onAccent,
                    disabledBackgroundColor: Wa.disabled,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Send template'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
