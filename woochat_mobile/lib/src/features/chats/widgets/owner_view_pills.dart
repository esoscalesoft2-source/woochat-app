import 'package:flutter/material.dart';

import '../../../models/chat_attention.dart';
import '../../../theme/wa_colors.dart';

/// All · Mine · Chatbot — the web sidebar's segmented control. Mine lights up
/// rose, the others in the accent; a count shows only when there is one.
class OwnerViewPills extends StatelessWidget {
  const OwnerViewPills({
    super.key,
    required this.view,
    required this.counts,
    required this.onChanged,
  });

  final OwnerView view;
  final Map<OwnerView, int> counts;
  final ValueChanged<OwnerView> onChanged;

  static const List<(OwnerView, String, String)> _pills =
      <(OwnerView, String, String)>[
        (OwnerView.all, 'All', 'Every chat'),
        (
          OwnerView.mine,
          'Mine',
          'Chats waiting on you — an alert you got, or a chat passed to you, '
              'with no reply yet',
        ),
        (OwnerView.bot, 'Chatbot', 'Chats the AI is answering'),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Wa.chipInactiveBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (value, label, hint) in _pills)
            _Pill(
              label: switch (counts[value] ?? 0) {
                0 => label,
                final n => '$label ($n)',
              },
              hint: hint,
              active: view == value,
              activeColor: value == OwnerView.mine ? Wa.mine : Wa.accent,
              onTap: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.hint,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hint,
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : Wa.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
