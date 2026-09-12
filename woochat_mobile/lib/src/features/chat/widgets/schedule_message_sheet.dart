import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/wa_colors.dart';

/// When the user chose to send, and what was typed at the time.
class ScheduledSend {
  const ScheduledSend({required this.at, required this.text});

  final DateTime at;
  final String text;
}

/// "Schedule message", as a sheet that slides up from the bottom rather than
/// a box dropped in the middle of the screen — the same surface the attach
/// menu, Templates and More filters already use.
///
/// Returns the chosen moment; the caller decides what to do with it.
Future<ScheduledSend?> showScheduleMessageSheet(
  BuildContext context, {
  required String draft,
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
    builder: (context) => _ScheduleMessageSheet(draft: draft),
  );
}

class _ScheduleMessageSheet extends StatefulWidget {
  const _ScheduleMessageSheet({required this.draft});

  final String draft;

  @override
  State<_ScheduleMessageSheet> createState() => _ScheduleMessageSheetState();
}

class _ScheduleMessageSheetState extends State<_ScheduleMessageSheet> {
  late DateTime _date = DateTime.now();
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(minutes: 10)),
  );

  DateTime get _at =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  bool get _isPast => _at.isBefore(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _darkPicker,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: _darkPicker,
    );
    if (picked != null && mounted) setState(() => _time = picked);
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
    final hasDraft = widget.draft.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the buttons clear of the keyboard when a picker opens one.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          // On a wide window the sheet spans the screen; the content should
          // not stretch with it. heightFactor pins the sheet to the height of
          // its content — a plain Center would fill the whole screen, since
          // isScrollControlled lets the sheet grow that far.
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            // A short window — or a phone with the keyboard up — leaves less
            // height than the content needs, so it scrolls rather than
            // overflowing.
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
                          label: 'Date',
                          value: DateFormat('d MMM yyyy').format(_date),
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Time',
                          value: _time.format(context),
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Thread.input,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      hasDraft
                          ? 'Scheduling: "${widget.draft.trim()}"'
                          : 'Type a message in the chat box to schedule it as a '
                                'normal message.',
                      style: const TextStyle(color: Thread.meta, fontSize: 13),
                    ),
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
                        onPressed: hasDraft && !_isPast
                            ? () => Navigator.of(context).pop(
                                ScheduledSend(
                                  at: _at,
                                  text: widget.draft.trim(),
                                ),
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Wa.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Wa.accent.withValues(
                            alpha: 0.4,
                          ),
                          // The app-wide filled button style is full width
                          // (`Size.fromHeight`), which is an INFINITE width.
                          // In a Row that is unbounded, so the sheet failed to
                          // lay out at all. This button sizes to its label.
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

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.onTap});

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.schedule, size: 16, color: Thread.meta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Thread.text, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
