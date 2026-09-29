import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/lead_activity_repository.dart';
import '../../../data/summaries_repository.dart';
import '../../../models/chat.dart';
import '../../../models/chat_filters.dart';
import '../../../theme/wa_colors.dart';
import '../../chats/widgets/contact_avatar.dart';

/// Everything known about the contact behind a chat, in one sheet — the same
/// facts the chat row shows, spelled out: who they are, which ad they came
/// from, what product they are on, who handles them, their labels and
/// categories, and every note left on them.
///
/// Opens as a full page, the way WhatsApp opens a contact's profile from
/// the chat header, with the summaries laid out in full like the web's
/// B2B panel.
Future<void> showContactInfoSheet(
  BuildContext context, {
  required Chat chat,
  required String? assignedName,
  required List<String> labels,
  required List<String> categories,
  required VoidCallback onCopyNumber,
  VoidCallback? onChangeAssignee,
  String? contactName,
  String? photoUrl,
  String? productName,
  List<Note> notes = const <Note>[],
  Future<List<ChatSummary>> Function()? loadSummaries,
  Future<ChatSummary> Function(String text)? addSummary,
  Future<List<LeadStageEvent>> Function()? loadLeadActivity,
}) {
  final name = contactName?.trim().isNotEmpty ?? false
      ? contactName!.trim()
      : chat.displayName;
  final adHeadline = chat.lastAdHeadline?.trim();
  final adThumbnail = chat.lastAdThumbnailUrl?.trim();
  final hasAd =
      (adHeadline?.isNotEmpty ?? false) || (adThumbnail?.isNotEmpty ?? false);

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: Wa.background,
        appBar: AppBar(
          backgroundColor: Wa.background,
          foregroundColor: Wa.title,
          elevation: 0,
          title: const Text('Contact info'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ContactAvatar(chat: chat, radius: 56, photoUrl: photoUrl),
                    const SizedBox(height: 14),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Thread.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (chat.shownPhone.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        chat.shownPhone,
                        style: const TextStyle(
                          color: Thread.meta,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: Wa.divider),
              const SizedBox(height: 8),
              if (chat.shownPhone.isNotEmpty)
                _Row(
                  icon: Icons.copy_outlined,
                  label: 'Copy number',
                  value: chat.shownPhone,
                  onTap: onCopyNumber,
                ),
              if (hasAd)
                _Row(
                  icon: Icons.campaign_outlined,
                  label: 'Came from ad',
                  value: adHeadline?.isNotEmpty ?? false
                      ? adHeadline!
                      : 'From ad',
                  valueColor: Wa.accent,
                  leadingImageUrl: adThumbnail,
                ),
              if (productName?.trim().isNotEmpty ?? false)
                _Row(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Product',
                  value: productName!.trim(),
                  valueColor: Wa.productChip,
                ),
              _Row(
                icon: Icons.person_outline,
                label: 'Assigned to',
                value: assignedName ?? 'Unassigned',
                onTap: onChangeAssignee,
              ),
              _Row(
                icon: Icons.sell_outlined,
                label: 'Labels',
                value: labels.isEmpty ? 'None' : labels.join(', '),
              ),
              _Row(
                icon: Icons.account_tree_outlined,
                label: 'Categories',
                value: categories.isEmpty ? 'None' : categories.join(', '),
              ),
              _Row(
                icon: Icons.schedule,
                label: 'Last message',
                value: chat.lastMessageAt == null
                    ? 'No messages yet'
                    : _when(chat.lastMessageAt!),
              ),
              _NotesSection(notes: notes),
              if (loadSummaries != null)
                _SummarySection(load: loadSummaries, add: addSummary),
              if (loadLeadActivity != null)
                _LeadActivitySection(load: loadLeadActivity),
            ],
          ),
        ),
      ),
    ),
  );
}

String _when(DateTime at) {
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  final time = TimeOfDay.fromDateTime(at);
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
  final clock = '$hour:$minute $suffix';
  return sameDay ? clock : '${at.day}/${at.month}/${at.year}, $clock';
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.valueColor,
    this.leadingImageUrl,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? valueColor;

  /// A small picture in front of the value — the ad thumbnail.
  final String? leadingImageUrl;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      style: TextStyle(color: valueColor ?? Thread.text, fontSize: 14.5),
    );
    final image = leadingImageUrl;

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: Wa.icon),
      title: Text(
        label,
        style: const TextStyle(color: Thread.meta, fontSize: 12),
      ),
      subtitle: image == null || image.isEmpty
          ? text
          : Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    image,
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: text),
              ],
            ),
    );
  }
}

/// Every note on the contact, newest first, or a single "None" line.
class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.notes});

  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const _Row(
        icon: Icons.sticky_note_2_outlined,
        label: 'Notes',
        value: 'None',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.sticky_note_2_outlined, size: 20, color: Wa.icon),
              SizedBox(width: 16),
              Text('Notes', style: TextStyle(color: Thread.meta, fontSize: 12)),
            ],
          ),
        ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Wa.input,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: Wa.note, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (note.text ?? '').trim().isEmpty
                        ? '(empty note)'
                        : note.text!.trim(),
                    style: const TextStyle(color: Thread.text, fontSize: 14),
                  ),
                  if (note.tags.isNotEmpty || note.createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        <String>[
                          if (note.createdAt != null)
                            _when(note.createdAt!.toLocal()),
                          for (final tag in note.tags) '#$tag',
                        ].join(' · '),
                        style: const TextStyle(
                          color: Thread.meta,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The conversation's summaries — the same list the web's B2B page and lead
/// card show. Collapsed to one row until tapped, then slides open with the
/// history newest first and an Add button.
class _SummarySection extends StatefulWidget {
  const _SummarySection({required this.load, required this.add});

  final Future<List<ChatSummary>> Function() load;
  final Future<ChatSummary> Function(String text)? add;

  @override
  State<_SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<_SummarySection> {
  late final Future<List<ChatSummary>> _future = widget.load();
  final _added = <ChatSummary>[];

  Future<void> _add() async {
    final text = await _askForSummary(context);
    if (text == null || !mounted) return;
    try {
      final summary = await widget.add!(text);
      if (mounted) setState(() => _added.insert(0, summary));
    } on SummaryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The section header: the same SUMMARY … Add + as the web's panel.
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: <Widget>[
              const Icon(Icons.summarize_outlined, size: 20, color: Wa.icon),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Summary',
                  style: TextStyle(color: Thread.meta, fontSize: 12),
                ),
              ),
              if (widget.add != null)
                OutlinedButton.icon(
                  key: const ValueKey<String>('summary-add'),
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Wa.accent,
                    side: const BorderSide(color: Wa.accent),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 36, top: 4, bottom: 8),
          child: FutureBuilder<List<ChatSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  '${snapshot.error}',
                  style: const TextStyle(color: Wa.error, fontSize: 12.5),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
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
              final all = <ChatSummary>[
                ..._added,
                ...snapshot.data!.where(
                  (s) => !_added.any((a) => a.id == s.id),
                ),
              ];
              if (all.isEmpty) {
                return const Text(
                  'Nothing yet.',
                  style: TextStyle(color: Thread.meta, fontSize: 14.5),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final summary in all) _SummaryCard(summary: summary),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ChatSummary summary;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (summary.dayNumber != null) 'Day ${summary.dayNumber}',
      if (summary.createdAt != null) _when(summary.createdAt!),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Wa.input,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: Wa.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.text,
            style: const TextStyle(color: Thread.text, fontSize: 14),
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                meta,
                style: const TextStyle(color: Thread.meta, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Every stage the lead behind this chat has moved through, newest first —
/// the web lead card's "Lead activity" panel, laid out under Summary in the
/// same way. Read-only: a trigger writes the history, and nothing here can.
class _LeadActivitySection extends StatefulWidget {
  const _LeadActivitySection({required this.load});

  final Future<List<LeadStageEvent>> Function() load;

  @override
  State<_LeadActivitySection> createState() => _LeadActivitySectionState();
}

class _LeadActivitySectionState extends State<_LeadActivitySection> {
  late final Future<List<LeadStageEvent>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LeadStageEvent>>(
      future: _future,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.timeline_outlined, size: 20, color: Wa.icon),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      count > 0 ? 'Lead activity ($count)' : 'Lead activity',
                      key: const ValueKey<String>('lead-activity-title'),
                      style: const TextStyle(color: Thread.meta, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4, bottom: 8),
              child: _body(snapshot),
            ),
          ],
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<LeadStageEvent>> snapshot) {
    if (snapshot.hasError) {
      return Text(
        '${snapshot.error}',
        style: const TextStyle(color: Wa.error, fontSize: 12.5),
      );
    }
    if (!snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Wa.accent),
          ),
        ),
      );
    }
    final events = snapshot.data!;
    if (events.isEmpty) {
      // Same wording as the web: a lead has no history until it next moves,
      // and that is not the panel being broken.
      return const Text(
        'No pipeline changes recorded yet. Moves are logged from now on.',
        style: TextStyle(color: Thread.meta, fontSize: 14.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final event in events) _StageEventCard(event: event),
      ],
    );
  }
}

class _StageEventCard extends StatelessWidget {
  const _StageEventCard({required this.event});

  final LeadStageEvent event;

  @override
  Widget build(BuildContext context) {
    const stamp = TextStyle(color: Thread.meta, fontSize: 11.5);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Wa.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (event.isBaseline)
            // No arrow: nobody recorded what it came from, and drawing one
            // would be inventing the half that is not known.
            Text(
              event.to,
              style: const TextStyle(
                color: Thread.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: event.from ?? 'New',
                    style: const TextStyle(color: Thread.meta),
                  ),
                  const TextSpan(text: '  →  ',
                      style: TextStyle(color: Thread.meta)),
                  TextSpan(
                    text: event.to,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              style: const TextStyle(color: Thread.text, fontSize: 14),
            ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                if (event.isBaseline) const TextSpan(text: 'as at '),
                TextSpan(text: _stamp(event.at)),
                // No user means nothing was pressed: the callback cron moved
                // it. Worth saying, or it reads as an unattributed change.
                if (event.isAutomatic) const TextSpan(text: ' · automatic'),
                if (event.by != null) ...<InlineSpan>[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: event.by,
                    style: const TextStyle(color: Wa.tickBlue),
                  ),
                ],
              ],
            ),
            style: stamp,
          ),
          if (event.isBaseline)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Where this lead stood when logging began — earlier moves '
                'were not recorded.',
                style: TextStyle(color: Thread.meta, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  /// "16 Sep 2026, 12:00 AM" — the web's format, day always spelt since the
  /// history spans days.
  static String _stamp(DateTime at) =>
      DateFormat('dd MMM yyyy, h:mm a').format(at);
}

/// The "Add summary" box. Returns the text, or null when dismissed.
Future<String?> _askForSummary(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Wa.sheet,
      title: const Text(
        'Add summary',
        style: TextStyle(color: Wa.title, fontSize: 17),
      ),
      content: TextField(
        key: const ValueKey<String>('summary-text'),
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: Wa.title, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'What was discussed, what was agreed…',
          hintStyle: const TextStyle(color: Wa.secondaryText),
          filled: true,
          fillColor: Wa.input,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Wa.secondaryText),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: Wa.accent,
            foregroundColor: Wa.onAccent,
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((value) => value == null || value.isEmpty ? null : value);
}
