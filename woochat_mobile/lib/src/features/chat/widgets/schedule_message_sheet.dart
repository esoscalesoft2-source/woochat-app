import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/templates_repository.dart';
import '../../../theme/wa_colors.dart';
import '../schedule_rules.dart';

/// What the dialog decided: when, and either the composer's own message or
/// a filled-in template.
class ScheduledSend {
  const ScheduledSend.freeForm({required this.at, required this.body})
      : template = null,
        params = const <int, String>{};

  const ScheduledSend.template({
    required this.at,
    required MessageTemplate this.template,
    required this.params,
  }) : body = '';

  final DateTime at;

  /// The message to queue, as it stands in the sheet's own box — the
  /// composer's text when it was opened with one, otherwise whatever was
  /// typed here. Empty for a template send, which carries [renderedBody].
  final String body;

  /// Null for a free-form send of whatever is in the composer.
  final MessageTemplate? template;

  /// `{{n}}` → value, for a template send.
  final Map<int, String> params;

  bool get isTemplate => template != null;

  /// The template body as the customer will read it — what the scheduled
  /// bubble shows meanwhile.
  String get renderedBody => template?.render(params) ?? '';

  /// The values in `{{n}}` order, trimmed, for `template_params`.
  List<String> get orderedParams => <String>[
        for (final n in template?.parameterNumbers ?? const <int>[])
          (params[n] ?? '').trim(),
      ];
}

/// "Schedule message" — pick a moment, and the dialog works out from the
/// customer's window whether the composer's text can go as it is or an
/// approved template is needed, switching its lower half accordingly.
///
/// Returns the choice, or null when dismissed.
Future<ScheduledSend?> showScheduleMessageSheet(
  BuildContext context, {
  required String draft,
  required bool hasStagedMedia,
  required DateTime? lastInboundAt,
  required Future<List<MessageTemplate>> Function() loadTemplates,
}) {
  return showModalBottomSheet<ScheduledSend>(
    context: context,
    backgroundColor: Wa.sheet,
    // The keyboard can come up behind the date/time pickers, and the sheet
    // has to be free to size itself around it.
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _ScheduleMessageSheet(
      draft: draft,
      hasStagedMedia: hasStagedMedia,
      lastInboundAt: lastInboundAt,
      loadTemplates: loadTemplates,
    ),
  );
}

class _ScheduleMessageSheet extends StatefulWidget {
  const _ScheduleMessageSheet({
    required this.draft,
    required this.hasStagedMedia,
    required this.lastInboundAt,
    required this.loadTemplates,
  });

  final String draft;
  final bool hasStagedMedia;
  final DateTime? lastInboundAt;
  final Future<List<MessageTemplate>> Function() loadTemplates;

  @override
  State<_ScheduleMessageSheet> createState() => _ScheduleMessageSheetState();
}

class _ScheduleMessageSheetState extends State<_ScheduleMessageSheet> {
  late DateTime _date;
  late TimeOfDay _time;

  /// The message being queued. Starts as whatever the composer held, so
  /// the old way — type in the chat box, then open the clock — still works,
  /// and stays editable here.
  late final TextEditingController _body =
      TextEditingController(text: widget.draft);

  Future<List<MessageTemplate>>? _templates;
  MessageTemplate? _template;
  final _params = <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final start = DateTime.now().add(const Duration(minutes: 10));
    _date = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay.fromDateTime(start);
    // A closed window means the template list is needed straight away.
    if (!_withinWindow) _templates = widget.loadTemplates();
  }

  @override
  void dispose() {
    _body.dispose();
    for (final controller in _params.values) {
      controller.dispose();
    }
    super.dispose();
  }

  DateTime get _at =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  bool get _isPast => _at.isBefore(DateTime.now());

  bool get _withinWindow => ScheduleRules.withinWindow(widget.lastInboundAt, _at);

  bool get _hasFreeForm =>
      _body.text.trim().isNotEmpty || widget.hasStagedMedia;

  Map<int, String> get _paramValues => <int, String>{
        for (final entry in _params.entries) entry.key: entry.value.text.trim(),
      };

  bool get _templateReady {
    final template = _template;
    if (template == null) return false;
    final values = _paramValues;
    return template.parameterNumbers.every((n) => (values[n] ?? '').isNotEmpty);
  }

  bool get _canSchedule =>
      !_isPast && (_withinWindow ? _hasFreeForm : _templateReady);

  void _afterTimeChange() {
    setState(() {
      if (!_withinWindow) _templates ??= widget.loadTemplates();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _darkPicker,
    );
    if (picked != null && mounted) {
      _date = picked;
      _afterTimeChange();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: _darkPicker,
    );
    if (picked != null && mounted) {
      _time = picked;
      _afterTimeChange();
    }
  }

  void _chooseTemplate(MessageTemplate? template) {
    setState(() {
      _template = template;
      for (final controller in _params.values) {
        controller.dispose();
      }
      _params.clear();
      for (final n in template?.parameterNumbers ?? const <int>[]) {
        _params[n] = TextEditingController();
      }
    });
  }

  void _submit() {
    if (!_canSchedule) return;
    Navigator.of(context).pop(
      _withinWindow
          ? ScheduledSend.freeForm(at: _at, body: _body.text.trim())
          : ScheduledSend.template(
              at: _at,
              template: _template!,
              params: _paramValues,
            ),
    );
  }

  static Widget _darkPicker(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Wa.accent,
            onPrimary: Wa.onAccent,
            surface: Thread.composer,
          ),
        ),
        child: child!,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the buttons clear of the keyboard when a picker opens one.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          // On a wide window the sheet spans the screen; the content should
          // not stretch with it. heightFactor pins the sheet to the height
          // of its content — a plain Center would fill the whole screen.
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.schedule, size: 18, color: Wa.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Schedule message',
                          style: TextStyle(
                            color: Thread.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                        color: Thread.meta,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick when this message should be sent.',
                    style: TextStyle(color: Thread.meta, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _Field(
                          key: const ValueKey<String>('schedule-date'),
                          label: 'Date',
                          value: DateFormat('d MMM yyyy').format(_date),
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          key: const ValueKey<String>('schedule-time'),
                          label: 'Time',
                          value: _time.format(context),
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_withinWindow)
                    _MessageBox(
                      key: const ValueKey<String>('schedule-freeform'),
                      controller: _body,
                      // Nothing to carry over means they came here to write
                      // it, so put the caret in the box for them.
                      autofocus: widget.draft.trim().isEmpty &&
                          !widget.hasStagedMedia,
                      stagedMedia: widget.hasStagedMedia,
                      onChanged: () => setState(() {}),
                    )
                  else
                    _TemplateBox(
                      templates: _templates!,
                      selected: _template,
                      params: _params,
                      onSelect: _chooseTemplate,
                      onParamChanged: () => setState(() {}),
                    ),
                  if (_isPast) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text(
                      'That moment has already passed.',
                      style: TextStyle(color: Wa.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Thread.text,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const ValueKey<String>('schedule-submit'),
                        onPressed: _canSchedule ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Wa.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Wa.accent.withValues(
                            alpha: 0.4,
                          ),
                          // The app-wide filled button style is full width,
                          // which is unbounded in a Row. This one sizes to
                          // its label.
                          minimumSize: const Size(0, 44),
                        ),
                        child: const Text('Schedule'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The amber box for a time the composer's text cannot reach: pick an
/// approved template, fill its `{{n}}`s, and see it rendered.
class _TemplateBox extends StatelessWidget {
  const _TemplateBox({
    required this.templates,
    required this.selected,
    required this.params,
    required this.onSelect,
    required this.onParamChanged,
  });

  final Future<List<MessageTemplate>> templates;
  final MessageTemplate? selected;
  final Map<int, TextEditingController> params;
  final ValueChanged<MessageTemplate?> onSelect;
  final VoidCallback onParamChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('schedule-template-box'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.warningBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Wa.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 16, color: Wa.warning),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'That time is outside the 24-hour window, so it must go '
                  'as a template.',
                  style: TextStyle(color: Thread.text, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<MessageTemplate>>(
            future: templates,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load templates: ${snapshot.error}',
                  style: const TextStyle(color: Wa.error, fontSize: 12),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Wa.accent,
                      ),
                    ),
                  ),
                );
              }
              final list = snapshot.data!;
              if (list.isEmpty) {
                return const Text(
                  'No approved templates yet. Create and submit one in Meta.',
                  style: TextStyle(color: Thread.meta, fontSize: 12.5),
                );
              }
              return DropdownButtonFormField<MessageTemplate>(
                key: const ValueKey<String>('schedule-template'),
                initialValue: selected,
                isExpanded: true,
                dropdownColor: Wa.sheet,
                style: const TextStyle(color: Thread.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Pick a template',
                  hintStyle: const TextStyle(color: Thread.meta),
                  isDense: true,
                  filled: true,
                  fillColor: Thread.input,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: <DropdownMenuItem<MessageTemplate>>[
                  for (final template in list)
                    DropdownMenuItem<MessageTemplate>(
                      value: template,
                      child: Text(
                        template.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onSelect,
              );
            },
          ),
          if (selected != null) ...<Widget>[
            for (final n in selected!.parameterNumbers)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: ValueKey<String>('schedule-param-$n'),
                  controller: params[n],
                  onChanged: (_) => onParamChanged(),
                  style: const TextStyle(color: Thread.text, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '{{$n}}',
                    labelStyle: const TextStyle(color: Thread.meta),
                    isDense: true,
                    filled: true,
                    fillColor: Thread.input,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey<String>('schedule-preview'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Thread.outbound,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selected!.render(<int, String>{
                  for (final entry in params.entries)
                    entry.key: entry.value.text,
                }),
                style: const TextStyle(color: Thread.text, fontSize: 13.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The message to queue, written here.
///
/// It opens holding the composer's text, so scheduling what is already
/// typed in the chat box works as it always did — but it is a real box, so
/// a message can equally be written in the sheet without touching the
/// composer first.
class _MessageBox extends StatelessWidget {
  const _MessageBox({
    super.key,
    required this.controller,
    required this.autofocus,
    required this.stagedMedia,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool autofocus;

  /// Files are staged in the composer, so this text is their caption.
  final bool stagedMedia;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          stagedMedia ? 'Caption' : 'Message',
          style: const TextStyle(color: Thread.meta, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('schedule-message'),
          controller: controller,
          autofocus: autofocus,
          onChanged: (_) => onChanged(),
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Thread.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: stagedMedia
                ? 'Add a caption for the staged files (optional)'
                : 'Type the message to schedule',
            hintStyle: const TextStyle(color: Thread.meta, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: Thread.input,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Wa.accent),
            ),
          ),
        ),
        if (stagedMedia) ...<Widget>[
          const SizedBox(height: 6),
          const Text(
            'The staged files go with it.',
            style: TextStyle(color: Thread.meta, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(color: Thread.meta, fontSize: 12)),
        const SizedBox(height: 6),
        Material(
          color: Thread.input,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                value,
                style: const TextStyle(color: Thread.text, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
