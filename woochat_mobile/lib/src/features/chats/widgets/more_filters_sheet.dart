import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../models/chat_filters.dart';
import '../../../theme/wa_colors.dart';
import '../chat_filter_state.dart';
import 'chat_owners.dart';

/// The "More filters" panel behind the chevron.
///
/// On a phone the web app's nested dropdowns become one scrollable sheet with
/// expandable sections — same behaviour, reachable with a thumb. Every count
/// comes from the chat list already in memory.
Future<ChatFilterState?> showMoreFiltersSheet(
  BuildContext context, {
  required List<Chat> scopedChats,
  required ChatFilterData data,
  required ChatFilterState state,
  required String signedInUserId,
  String? signedInLabel,
  DateTimeRangeMs? range,
}) {
  return showModalBottomSheet<ChatFilterState>(
    context: context,
    backgroundColor: Wa.background,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _MoreFiltersSheet(
      scopedChats: scopedChats,
      data: data,
      state: state,
      range: range,
      signedInUserId: signedInUserId,
      signedInLabel: signedInLabel,
    ),
  );
}

class _MoreFiltersSheet extends StatefulWidget {
  const _MoreFiltersSheet({
    required this.scopedChats,
    required this.data,
    required this.state,
    required this.range,
    required this.signedInUserId,
    required this.signedInLabel,
  });

  final List<Chat> scopedChats;
  final ChatFilterData data;
  final ChatFilterState state;
  final DateTimeRangeMs? range;
  final String signedInUserId;
  final String? signedInLabel;

  @override
  State<_MoreFiltersSheet> createState() => _MoreFiltersSheetState();
}

class _MoreFiltersSheetState extends State<_MoreFiltersSheet> {
  late final TextEditingController _noteKeyword =
      TextEditingController(text: widget.state.noteKeyword);

  /// Derived once: the loaded list does not change while the sheet is open.
  late final List<ChatOwner> _owners = ownersOf(
    widget.scopedChats,
    signedInUserId: widget.signedInUserId,
    signedInLabel: widget.signedInLabel,
  );

  @override
  void dispose() {
    _noteKeyword.dispose();
    super.dispose();
  }

  /// How many chats a candidate state would show, from the loaded list.
  int _count(ChatFilterState candidate) => ChatFilterEngine.count(
        chats: widget.scopedChats,
        data: widget.data,
        state: candidate,
        range: widget.range,
      );

  void _apply(ChatFilterState next) => Navigator.of(context).pop(next);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final data = widget.data;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'More filters',
                      style: TextStyle(
                        color: Wa.title,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (state.isNarrowed)
                    TextButton(
                      onPressed: () => _apply(state.clearAll()),
                      child: const Text(
                        'Clear all',
                        style: TextStyle(color: Wa.accent),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Wa.divider),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: <Widget>[
                  _Toggle(
                    icon: Icons.archive_outlined,
                    label: 'Archived',
                    count: _count(state.selectArchived()),
                    active: state.tab == ContactTab.archived,
                    onTap: () => _apply(
                      state.tab == ContactTab.archived
                          ? state.selectTab(ContactTab.all)
                          : state.selectArchived(),
                    ),
                  ),
                  _Toggle(
                    icon: Icons.error_outline,
                    label: 'Funnel failed',
                    subtitle: 'Funnel messages WhatsApp could not deliver',
                    count: _count(
                      state.funnelFailed ? state : state.toggleFunnelFailed(),
                    ),
                    active: state.funnelFailed,
                    onTap: () => _apply(state.toggleFunnelFailed()),
                  ),
                  _Section(
                    icon: Icons.label_outline,
                    title: 'Labels',
                    value: _labelValue(),
                    children: <Widget>[
                      _Option(
                        label: 'All Labels',
                        selected: state.labelId == null,
                        onTap: () => _apply(state.selectLabel(null)),
                      ),
                      for (final label in data.dedupedLabels)
                        _Option(
                          label: label.name,
                          colorDot: _parseColor(label.color),
                          count: _count(state.selectLabel(label.id)),
                          selected: _labelSelected(label),
                          onTap: () => _apply(state.selectLabel(label.id)),
                        ),
                      _Option(
                        label: 'UnAssigned',
                        count: _count(
                          state.selectLabel(FilterSentinel.unassignedLabel),
                        ),
                        selected:
                            state.labelId == FilterSentinel.unassignedLabel,
                        onTap: () => _apply(
                          state.selectLabel(FilterSentinel.unassignedLabel),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    icon: Icons.category_outlined,
                    title: 'Categories',
                    value: _nameOf(
                      data.categories
                          .where((c) => c.id == state.categoryId)
                          .map((c) => c.name),
                      state.categoryId,
                      FilterSentinel.unassignedCategory,
                    ),
                    children: <Widget>[
                      _Option(
                        label: 'All Categories',
                        selected: state.categoryId == null,
                        onTap: () => _apply(state.selectCategory(null)),
                      ),
                      for (final category in data.categories)
                        _Option(
                          label: category.name,
                          colorDot: _parseColor(category.color),
                          count: _count(state.selectCategory(category.id)),
                          selected: state.categoryId == category.id,
                          onTap: () => _apply(
                            state.selectCategory(category.id),
                          ),
                        ),
                      _Option(
                        label: 'UnAssigned',
                        count: _count(
                          state
                              .selectCategory(FilterSentinel.unassignedCategory),
                        ),
                        selected: state.categoryId ==
                            FilterSentinel.unassignedCategory,
                        onTap: () => _apply(
                          state
                              .selectCategory(FilterSentinel.unassignedCategory),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Products',
                    value: _nameOf(
                      data.products
                          .where((p) => p.id == state.productId)
                          .map((p) => p.title),
                      state.productId,
                      FilterSentinel.unassignedProduct,
                    ),
                    children: <Widget>[
                      _Option(
                        label: 'All Products',
                        selected: state.productId == null,
                        onTap: () => _apply(state.selectProduct(null)),
                      ),
                      for (final product in data.products)
                        _Option(
                          label: product.title,
                          count: _count(state.selectProduct(product.id)),
                          selected: state.productId == product.id,
                          onTap: () => _apply(state.selectProduct(product.id)),
                        ),
                      _Option(
                        label: 'UnAssigned',
                        count: _count(
                          state.selectProduct(FilterSentinel.unassignedProduct),
                        ),
                        selected:
                            state.productId == FilterSentinel.unassignedProduct,
                        onTap: () => _apply(
                          state.selectProduct(FilterSentinel.unassignedProduct),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    icon: Icons.campaign_outlined,
                    title: 'Lead source',
                    value: switch (state.source) {
                      null => null,
                      LeadSource.ads => 'Meta Ads',
                      LeadSource.organic => 'Organic',
                    },
                    children: <Widget>[
                      _Option(
                        label: 'All sources',
                        selected: state.source == null,
                        onTap: () => _apply(state.selectSource(null)),
                      ),
                      _Option(
                        label: 'Meta Ads',
                        count: _count(state.selectSource(LeadSource.ads)),
                        selected: state.source == LeadSource.ads,
                        onTap: () => _apply(state.selectSource(LeadSource.ads)),
                      ),
                      _Option(
                        label: 'Organic',
                        count: _count(state.selectSource(LeadSource.organic)),
                        selected: state.source == LeadSource.organic,
                        onTap: () =>
                            _apply(state.selectSource(LeadSource.organic)),
                      ),
                    ],
                  ),
                  _Section(
                    icon: Icons.bolt_outlined,
                    title: 'Auto Reply',
                    value: _automationValue(),
                    children: <Widget>[
                      _Option(
                        label: 'Clear Filter',
                        selected: state.automationId == null,
                        onTap: () => _apply(state.selectAutomation(null)),
                      ),
                      _Option(
                        label: 'All Automations',
                        count: _count(
                          state.selectAutomation(FilterSentinel.automationAll),
                        ),
                        selected:
                            state.automationId == FilterSentinel.automationAll,
                        onTap: () => _apply(
                          state.selectAutomation(FilterSentinel.automationAll),
                        ),
                      ),
                      _Option(
                        label: 'Replied',
                        subtitle: 'Answered a funnel message in the dates '
                            'picked above',
                        count: _count(
                          state
                              .selectAutomation(FilterSentinel.automationReplied),
                        ),
                        selected: state.automationId ==
                            FilterSentinel.automationReplied,
                        onTap: () => _apply(
                          state
                              .selectAutomation(FilterSentinel.automationReplied),
                        ),
                      ),
                      for (final automation in data.automations)
                        _Option(
                          label: automation.name,
                          count: _count(state.selectAutomation(automation.id)),
                          selected: state.automationId == automation.id,
                          onTap: () =>
                              _apply(state.selectAutomation(automation.id)),
                        ),
                    ],
                  ),
                  // Team user lived in the header until the pills came out;
                  // it belongs with the other filters anyway.
                  _Section(
                    icon: Icons.people_outline,
                    title: 'Team user',
                    value: _ownerValue(),
                    children: <Widget>[
                      _Option(
                        label: 'All users',
                        selected: state.ownerId == null,
                        onTap: () => _apply(state.selectOwner(null)),
                      ),
                      for (final owner in _owners)
                        _Option(
                          label: owner.label,
                          count: owner.count,
                          selected: state.ownerId == owner.userId,
                          onTap: () => _apply(state.selectOwner(owner.userId)),
                        ),
                      if (_owners.length < 2)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(32, 4, 16, 8),
                          child: Text(
                            'Every loaded conversation has the same owner, so '
                            'there is nothing to split by yet.',
                            style: TextStyle(
                              color: Wa.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  _Section(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'Notes',
                    value: state.noteTag ??
                        (state.noteKeyword.isEmpty ? null : state.noteKeyword),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: TextField(
                          controller: _noteKeyword,
                          style: const TextStyle(color: Wa.title, fontSize: 14),
                          cursorColor: Wa.accent,
                          onSubmitted: (value) =>
                              _apply(state.applyNoteKeyword(value)),
                          decoration: InputDecoration(
                            hintText: 'Search notes and tags',
                            hintStyle: const TextStyle(
                              color: Wa.secondaryText,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: Wa.chipInactiveBackground,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.check, size: 18),
                              color: Wa.accent,
                              tooltip: 'Apply filter',
                              onPressed: () => _apply(
                                state.applyNoteKeyword(_noteKeyword.text),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _Option(
                        label: 'Clear note filters',
                        selected: !state.hasNoteFilter,
                        onTap: () => _apply(state.clearNoteFilters()),
                      ),
                      if (data.noteTags.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'TAGS',
                            style: TextStyle(
                              color: Wa.secondaryText,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      for (final tag in data.noteTags)
                        _Option(
                          label: tag,
                          count: _count(state.selectNoteTag(tag)),
                          selected: state.noteTag == tag,
                          onTap: () => _apply(state.selectNoteTag(tag)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _labelSelected(Label label) {
    final selected = widget.state.labelId;
    if (selected == null || selected == FilterSentinel.unassignedLabel) {
      return false;
    }
    return widget.data.idsSharingNameWith(selected).contains(label.id);
  }

  String? _labelValue() {
    final id = widget.state.labelId;
    if (id == null) return null;
    if (id == FilterSentinel.unassignedLabel) return 'UnAssigned';
    return widget.data.labels
        .where((label) => label.id == id)
        .map((label) => label.name)
        .firstOrNull;
  }

  String? _ownerValue() {
    final id = widget.state.ownerId;
    if (id == null) return null;
    return _owners
        .where((owner) => owner.userId == id)
        .map((owner) => owner.label)
        .firstOrNull;
  }

  String? _automationValue() {
    final id = widget.state.automationId;
    return switch (id) {
      null => null,
      FilterSentinel.automationAll => 'All Automations',
      FilterSentinel.automationReplied => 'Replied',
      _ => widget.data.automations
          .where((automation) => automation.id == id)
          .map((automation) => automation.name)
          .firstOrNull,
    };
  }

  static String? _nameOf(
    Iterable<String> matches,
    String? selected,
    String unassignedSentinel,
  ) {
    if (selected == null) return null;
    if (selected == unassignedSentinel) return 'UnAssigned';
    return matches.firstOrNull;
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final hex = value.replaceFirst('#', '').trim();
    if (hex.length != 6) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: active ? Wa.accent : Wa.icon),
      title: Text(
        label,
        style: TextStyle(color: active ? Wa.accent : Wa.title),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 12),
            ),
      trailing: _CountBadge(count: count, active: active),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.value,
    required this.children,
  });

  final IconData icon;
  final String title;

  /// The current selection, shown beside the title.
  final String? value;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final active = value != null;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: active ? Wa.accent : Wa.icon),
        title: Text(
          title,
          style: TextStyle(color: active ? Wa.accent : Wa.title),
        ),
        subtitle: active
            ? Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Wa.secondaryText, fontSize: 12),
              )
            : null,
        iconColor: Wa.accent,
        collapsedIconColor: Wa.icon,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children,
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.subtitle,
    this.colorDot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final String? subtitle;
  final Color? colorDot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: colorDot == null
          ? null
          : Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: colorDot, shape: BoxShape.circle),
            ),
      horizontalTitleGap: colorDot == null ? 0 : 8,
      minLeadingWidth: colorDot == null ? 0 : 10,
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? Wa.accent : Wa.title,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 11),
            ),
      trailing: count == null
          ? (selected ? const Icon(Icons.check, size: 18, color: Wa.accent) : null)
          : _CountBadge(count: count!, active: selected),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.active});

  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // No `alignment` here: a Container with one expands to fill its
    // constraints, and ListTile gives `trailing` the full tile width.
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? Wa.accent : Wa.chipInactiveBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? Colors.white : Wa.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
