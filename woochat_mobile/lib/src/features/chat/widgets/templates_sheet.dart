import 'package:flutter/material.dart';

import '../../../data/templates_repository.dart';
import '../../../theme/wa_colors.dart';
import 'create_template_sheet.dart';

/// Lists the approved WhatsApp templates for this workspace, with a `+` that
/// opens the Create Template sheet.
///
/// Only APPROVED templates can be sent outside the 24-hour window, so only
/// those are listed — the same filter the web app applies. A template made
/// here goes to Meta for review, so it joins the list once approved.
///
/// Tapping a template closes this sheet and hands the template back, so the
/// caller can collect its values and send it. Null when dismissed.
Future<MessageTemplate?> showTemplatesSheet(
  BuildContext context, {
  required Future<List<MessageTemplate>> Function() load,
  required String chatName,
  Future<List<SavedParameter>> Function()? loadParameters,
  Future<SavedParameter> Function(String name)? saveParameter,
  Future<void> Function(TemplateDraft draft)? create,
}) {
  return showModalBottomSheet<MessageTemplate>(
    context: context,
    backgroundColor: Thread.composer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _TemplatesSheet(
      load: load,
      chatName: chatName,
      loadParameters: loadParameters,
      saveParameter: saveParameter,
      create: create,
    ),
  );
}

class _TemplatesSheet extends StatefulWidget {
  const _TemplatesSheet({
    required this.load,
    required this.chatName,
    required this.loadParameters,
    required this.saveParameter,
    required this.create,
  });

  final Future<List<MessageTemplate>> Function() load;
  final String chatName;
  final Future<List<SavedParameter>> Function()? loadParameters;
  final Future<SavedParameter> Function(String name)? saveParameter;
  final Future<void> Function(TemplateDraft draft)? create;

  @override
  State<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends State<_TemplatesSheet> {
  late Future<List<MessageTemplate>> _future = widget.load();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Name or body, any case. With 280-odd approved templates the list is
  /// not something to scroll; the name is what people remember.
  List<MessageTemplate> _matching(List<MessageTemplate> all) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return all;
    return <MessageTemplate>[
      for (final template in all)
        if (template.name.toLowerCase().contains(query) ||
            (template.body?.toLowerCase().contains(query) ?? false))
          template,
    ];
  }

  /// Creating is possible only when the caller wired all three pieces.
  bool get _canCreate =>
      widget.create != null &&
      widget.loadParameters != null &&
      widget.saveParameter != null;

  Future<void> _openCreate() async {
    final created = await showCreateTemplateSheet(
      context,
      loadParameters: widget.loadParameters!,
      saveParameter: widget.saveParameter!,
      create: widget.create!,
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Template submitted to Meta. It appears here once approved.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      setState(() => _future = widget.load());
    }
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
                      'Approved templates',
                      style: TextStyle(
                        color: Thread.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_canCreate)
                    IconButton(
                      onPressed: _openCreate,
                      tooltip: 'Create template',
                      icon: const Icon(Icons.add, color: Wa.accent),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'The 24-hour window with ${widget.chatName} is closed, so '
                'WhatsApp accepts an approved template only.',
                style: const TextStyle(color: Thread.meta, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                key: const ValueKey<String>('templates-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Thread.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search templates',
                  hintStyle: const TextStyle(color: Thread.meta, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Wa.icon, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Wa.icon,
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Thread.input,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Wa.accent, width: 1.5),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Wa.divider),
            Flexible(
              child: FutureBuilder<List<MessageTemplate>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _Message(
                      text: 'Could not load templates.\n${snapshot.error}',
                      onRetry: () =>
                          setState(() => _future = widget.load()),
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

                  final all = snapshot.data!;
                  if (all.isEmpty) {
                    return const _Message(
                      text: 'No approved templates yet. Create and submit one '
                          'in Meta, then it appears here.',
                    );
                  }
                  final templates = _matching(all);
                  if (templates.isEmpty) {
                    return _Message(
                      text: 'No template matches "${_search.text.trim()}".',
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: templates.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Wa.divider),
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(template),
                        leading: const Icon(
                          Icons.description_outlined,
                          color: Wa.accent,
                        ),
                        title: Text(
                          template.name,
                          style: const TextStyle(color: Thread.text),
                        ),
                        subtitle: Text(
                          template.body?.replaceAll('\n', ' ') ??
                              (template.language ?? ''),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Thread.meta,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Tap a template to fill in its values and send it.',
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
