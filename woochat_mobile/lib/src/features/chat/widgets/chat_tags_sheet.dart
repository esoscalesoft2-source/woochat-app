import 'package:flutter/material.dart';

import '../../../theme/wa_colors.dart';

/// One option in the labels or categories picker.
class TagOption {
  const TagOption({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;
}

/// The labels / categories picker behind the two header buttons.
///
/// It slides up like every other surface in the app. Toggling writes straight
/// away through [onToggle] rather than collecting changes behind a Save, which
/// is what the web app does — the tick reflects the row that now exists.
///
/// [singleSelect] makes it a chooser rather than a set of toggles: ticking one
/// option clears whichever was ticked before, and ticking the ticked one
/// clears it — the way the Products menu works, since a customer holds one
/// product. [onToggle] is still called once per tap, with the row that was
/// tapped.
Future<void> showChatTagsSheet(
  BuildContext context, {
  required String title,
  required String emptyMessage,
  required List<TagOption> options,
  required Set<String> selected,
  required Future<bool> Function(String id, bool applied) onToggle,
  bool singleSelect = false,
  IconData? leadingIcon,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _ChatTagsSheet(
      title: title,
      emptyMessage: emptyMessage,
      options: options,
      selected: selected,
      onToggle: onToggle,
      singleSelect: singleSelect,
      leadingIcon: leadingIcon,
    ),
  );
}

class _ChatTagsSheet extends StatefulWidget {
  const _ChatTagsSheet({
    required this.title,
    required this.emptyMessage,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.singleSelect,
    required this.leadingIcon,
  });

  final String title;
  final String emptyMessage;
  final List<TagOption> options;
  final Set<String> selected;
  final Future<bool> Function(String id, bool applied) onToggle;
  final bool singleSelect;

  /// Drawn instead of the colour dot when the options have no colour.
  final IconData? leadingIcon;

  @override
  State<_ChatTagsSheet> createState() => _ChatTagsSheetState();
}

class _ChatTagsSheetState extends State<_ChatTagsSheet> {
  late final Set<String> _selected = <String>{...widget.selected};

  /// The row waiting on the database, so it can show a spinner and refuse a
  /// second tap while the write is in flight.
  String? _busyId;

  Future<void> _toggle(TagOption option) async {
    if (_busyId != null) return;

    final applied = !_selected.contains(option.id);
    setState(() => _busyId = option.id);

    final ok = await widget.onToggle(option.id, applied);

    if (!mounted) return;
    setState(() {
      _busyId = null;
      // Only move the tick once the row is actually there (or gone).
      if (ok) {
        if (applied) {
          if (widget.singleSelect) _selected.clear();
          _selected.add(option.id);
        } else {
          _selected.remove(option.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Thread.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: Wa.divider),
            if (widget.options.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Text(
                  widget.emptyMessage,
                  style: const TextStyle(color: Thread.meta, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final option = widget.options[index];
                    final on = _selected.contains(option.id);

                    return ListTile(
                      onTap: () => _toggle(option),
                      leading: widget.leadingIcon != null && option.color == null
                          ? Icon(widget.leadingIcon, size: 20, color: Wa.productChip)
                          : _Dot(color: _parseColor(option.color)),
                      title: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: on ? Wa.accent : Thread.text,
                          fontSize: 15,
                        ),
                      ),
                      trailing: _busyId == option.id
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Wa.accent,
                              ),
                            )
                          : (on
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Wa.accent,
                                )
                              : null),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final hex = value.replaceFirst('#', '').trim();
    if (hex.length != 6) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: 24,
      child: Center(
        child: Container(
          height: 12,
          width: 12,
          decoration: BoxDecoration(
            color: color ?? Wa.chipInactiveBackground,
            shape: BoxShape.circle,
            border: color == null
                ? Border.all(color: Thread.meta, width: 1)
                : null,
          ),
        ),
      ),
    );
  }
}
