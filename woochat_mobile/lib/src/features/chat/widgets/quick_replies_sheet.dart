import 'package:flutter/material.dart';

import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';
import 'confirm_dialog.dart';

/// Lists the workspace's saved quick replies, with a `+` that opens the New
/// quick reply sheet — the same shape as the Approved templates sheet.
///
/// Tapping one closes the sheet and hands it back so the caller can put it
/// into the message box. Null when dismissed.
/// [edit] opens the reply for changes and returns the updated one; [delete]
/// removes it. Both are optional — without them the rows carry no icons.
/// [canManage] decides per reply whether they are offered at all.
Future<QuickReply?> showQuickRepliesSheet(
  BuildContext context, {
  required Future<List<QuickReply>> Function() load,
  Future<QuickReply?> Function()? create,
  Future<QuickReply?> Function(QuickReply reply)? edit,
  Future<void> Function(QuickReply reply)? delete,
  bool Function(QuickReply reply)? canManage,
}) {
  return showModalBottomSheet<QuickReply>(
    context: context,
    backgroundColor: Thread.composer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _QuickRepliesSheet(
      load: load,
      create: create,
      edit: edit,
      delete: delete,
      canManage: canManage,
    ),
  );
}

class _QuickRepliesSheet extends StatefulWidget {
  const _QuickRepliesSheet({
    required this.load,
    required this.create,
    required this.edit,
    required this.delete,
    required this.canManage,
  });

  final Future<List<QuickReply>> Function() load;
  final Future<QuickReply?> Function()? create;
  final Future<QuickReply?> Function(QuickReply reply)? edit;
  final Future<void> Function(QuickReply reply)? delete;
  final bool Function(QuickReply reply)? canManage;

  @override
  State<_QuickRepliesSheet> createState() => _QuickRepliesSheetState();
}

class _QuickRepliesSheetState extends State<_QuickRepliesSheet> {
  late Future<List<QuickReply>> _future = widget.load();

  /// Replies changed or removed since the list was fetched, so the sheet does
  /// not have to re-read every row after each edit.
  final _edited = <String, QuickReply>{};
  final _deleted = <String>{};

  String? _error;

  List<QuickReply> _visible(List<QuickReply> loaded) => <QuickReply>[
        for (final reply in loaded)
          if (!_deleted.contains(reply.id)) _edited[reply.id] ?? reply,
      ];

  bool _manageable(QuickReply reply) =>
      (widget.edit != null || widget.delete != null) &&
      (widget.canManage?.call(reply) ?? true);

  Future<void> _edit(QuickReply reply) async {
    final updated = await widget.edit!(reply);
    if (updated == null || !mounted) return;
    setState(() => _edited[reply.id] = updated);
  }

  Future<void> _delete(QuickReply reply) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete /${reply.title}?',
      message: 'This quick reply will be removed for everyone in the '
          'workspace. This cannot be undone.',
    );
    if (!confirmed || !mounted) return;

    try {
      await widget.delete!(reply);
      if (mounted) {
        setState(() {
          _deleted.add(reply.id);
          _error = null;
        });
      }
    } on ShortcutException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not delete the quick reply: $error');
      }
    }
  }

  Future<void> _openCreate() async {
    final reply = await widget.create!();
    if (reply == null || !mounted) return;
    // The new reply is the one they just wrote, so hand it straight over
    // rather than making them find it in the refreshed list.
    Navigator.of(context).pop(reply);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Quick replies',
                      style: TextStyle(
                        color: Thread.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.create != null)
                    IconButton(
                      onPressed: _openCreate,
                      tooltip: 'New quick reply',
                      icon: const Icon(Icons.add, color: Wa.accent),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Saved replies for this workspace. Typing / in the message '
                'box finds them too.',
                style: TextStyle(color: Thread.meta, fontSize: 12),
              ),
            ),
            const Divider(height: 1, color: Wa.divider),
            Flexible(
              child: FutureBuilder<List<QuickReply>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _Message(
                      text: 'Could not load quick replies.\n${snapshot.error}',
                      onRetry: () => setState(() => _future = widget.load()),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: Wa.accent),
                      ),
                    );
                  }

                  final replies = _visible(snapshot.data!);
                  if (replies.isEmpty) {
                    return _Message(
                      text: widget.create == null
                          ? 'No quick replies saved yet.'
                          : 'No quick replies yet. Tap + to save your first '
                              'one.',
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: replies.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Wa.divider),
                    itemBuilder: (context, index) {
                      final reply = replies[index];
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(reply),
                        leading: const Icon(Icons.bolt, color: Wa.quickReply),
                        trailing: !_manageable(reply)
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (widget.edit != null)
                                    IconButton(
                                      onPressed: () => _edit(reply),
                                      tooltip: 'Edit /${reply.title}',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                        color: Thread.meta,
                                      ),
                                    ),
                                  if (widget.delete != null)
                                    IconButton(
                                      onPressed: () => _delete(reply),
                                      tooltip: 'Delete /${reply.title}',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 19,
                                        color: Wa.error,
                                      ),
                                    ),
                                ],
                              ),
                        title: Text(
                          '/${reply.title}',
                          style: const TextStyle(color: Thread.text),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              reply.preview.replaceAll('\n', ' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Thread.meta,
                                fontSize: 12,
                              ),
                            ),
                            if (reply.message.isNotEmpty && reply.hasMedia)
                              Text(
                                reply.mediaLabel,
                                style: const TextStyle(
                                  color: Wa.accent,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Wa.error, fontSize: 12),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Tap a reply to put it in the message box.',
                style: TextStyle(color: Thread.meta, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Thread.meta, fontSize: 13),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
