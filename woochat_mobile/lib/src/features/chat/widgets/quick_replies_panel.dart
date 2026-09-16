import 'package:flutter/material.dart';

import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';

/// The slash token currently being typed, or null when the field is not in a
/// quick-reply lookup.
///
/// Only a `/` at the very start counts, and only while nothing else has been
/// typed after it but the trigger word — so a message that merely mentions a
/// URL or a date never opens the menu.
String? quickReplyQuery(String text) {
  if (!text.startsWith('/')) return null;
  final token = text.substring(1);
  if (token.contains(RegExp(r'\s'))) return null;
  return token;
}

/// The replies matching [query], best first.
///
/// A title that starts with what was typed ranks above one that merely
/// contains it, which is what makes typing `/50` land on `/50step1` rather
/// than something that happens to have "50" in the middle.
List<QuickReply> filterQuickReplies(List<QuickReply> all, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return all;

  final starts = <QuickReply>[];
  final contains = <QuickReply>[];

  for (final reply in all) {
    final title = reply.title.toLowerCase();
    if (title.startsWith(needle)) {
      starts.add(reply);
    } else if (title.contains(needle) ||
        reply.message.toLowerCase().contains(needle)) {
      contains.add(reply);
    }
  }

  return <QuickReply>[...starts, ...contains];
}

/// The list that opens above the input bar when `/` is typed.
class QuickRepliesPanel extends StatelessWidget {
  const QuickRepliesPanel({
    super.key,
    required this.replies,
    required this.loading,
    required this.onPick,
    this.maxHeight = 220,
  });

  final List<QuickReply> replies;
  final bool loading;
  final ValueChanged<QuickReply> onPick;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: Thread.composer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Wa.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch ((loading, replies.isEmpty)) {
        (true, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Wa.accent,
                ),
              ),
            ),
          ),
        (false, true) => const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Text(
              'No quick reply matches that.',
              style: TextStyle(color: Thread.meta, fontSize: 13),
            ),
          ),
        (false, false) => ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: replies.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Wa.divider),
            itemBuilder: (context, index) {
              final reply = replies[index];
              return InkWell(
                onTap: () => onPick(reply),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '/${reply.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Wa.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reply.preview.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: reply.message.isEmpty
                              ? Thread.meta
                              : Thread.text,
                          fontSize: 13,
                        ),
                      ),
                      // A reply with both text and files says so, the way the
                      // web list does.
                      if (reply.message.isNotEmpty && reply.hasMedia)
                        Text(
                          reply.mediaLabel,
                          style: const TextStyle(
                            color: Thread.meta,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      },
    );
  }
}
