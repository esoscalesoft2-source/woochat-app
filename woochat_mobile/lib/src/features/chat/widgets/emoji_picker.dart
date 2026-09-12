import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as ep;
import 'package:flutter/material.dart';

import '../../../theme/wa_colors.dart';

/// The emoji panel that slides in directly above the composer.
///
/// The emoji data comes from `emoji_picker_flutter` — the full Unicode set,
/// with names to search by and skin-tone support — but the layout is ours,
/// because the package's search is a whole replacement view rather than a
/// header, and pinning it above the grid left an empty strip.
///
/// Edge to edge and on the composer's own background, so it reads as part of
/// the keyboard area rather than a floating card.
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({super.key, required this.onPick, required this.height});

  final ValueChanged<String> onPick;
  final double height;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  /// The package's full English set. Empty categories (Recent starts empty)
  /// are dropped so no tab opens onto a blank grid.
  static final List<ep.CategoryEmoji> _categories = ep.defaultEmojiSet
      .where((category) => category.emoji.isNotEmpty)
      .toList();

  final _utils = ep.EmojiPickerUtils();
  final _searchController = TextEditingController();

  int _categoryIndex = 0;
  String _query = '';
  String? _skinTone;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Searching looks across every category, so a term is never hidden by
  /// whichever tab happens to be open.
  List<ep.Emoji> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _categories[_categoryIndex].emoji;

    return <ep.Emoji>[
      for (final category in _categories)
        ...category.emoji.where(
          (emoji) => emoji.name.toLowerCase().contains(query),
        ),
    ];
  }

  /// The chosen tone only applies to emoji that actually have variants, so a
  /// modifier is never appended where it would render as two glyphs.
  ep.Emoji _toned(ep.Emoji emoji) {
    final tone = _skinTone;
    if (tone == null || !emoji.hasSkinTone) return emoji;
    return _utils.applySkinTone(emoji, tone);
  }

  Future<void> _pickSkinTone() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Thread.composer,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Default skin tone',
                style: TextStyle(color: Thread.text, fontSize: 15),
              ),
            ),
            Wrap(
              children: <Widget>[
                for (final tone in <String?>[null, ...ep.SkinTone.values])
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(tone),
                    icon: Text(
                      tone == null ? '✋' : '✋$tone',
                      style: const TextStyle(fontSize: 24),
                    ),
                    tooltip: tone == null ? 'Default' : 'Skin tone',
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    // pop(null) also means "default", which is exactly what we want here.
    setState(() => _skinTone = picked);
  }

  @override
  Widget build(BuildContext context) {
    final emoji = _visible;
    final searching = _query.trim().isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: ColoredBox(
        color: Thread.background,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(
                        color: Thread.text,
                        fontSize: 14,
                      ),
                      cursorColor: Wa.accent,
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: const TextStyle(
                          color: Thread.meta,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 18,
                          color: Thread.meta,
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 38),
                        filled: true,
                        fillColor: Thread.input,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _pickSkinTone,
                    tooltip: 'Default skin tone',
                    icon: Text(
                      _skinTone == null ? '✋' : '✋$_skinTone',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
            ),
            if (!searching)
              _CategoryTabs(
                categories: _categories,
                selected: _categoryIndex,
                onSelected: (index) => setState(() => _categoryIndex = index),
              ),
            Expanded(
              child: emoji.isEmpty
                  ? const Center(
                      child: Text(
                        'No emoji match that search',
                        style: TextStyle(color: Thread.meta, fontSize: 13),
                      ),
                    )
                  : LayoutBuilder(
                      // Columns come from the width so the grid stays tight on
                      // a phone and does not spread out on a desktop window.
                      builder: (context, constraints) => GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 44,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        itemCount: emoji.length,
                        itemBuilder: (context, index) {
                          final toned = _toned(emoji[index]);
                          return InkWell(
                            onTap: () => widget.onPick(toned.emoji),
                            borderRadius: BorderRadius.circular(6),
                            child: Center(
                              child: Text(
                                toned.emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<ep.CategoryEmoji> categories;
  final int selected;
  final ValueChanged<int> onSelected;

  static const Map<ep.Category, IconData> _icons = <ep.Category, IconData>{
    ep.Category.RECENT: Icons.access_time,
    ep.Category.SMILEYS: Icons.emoji_emotions_outlined,
    ep.Category.ANIMALS: Icons.pets,
    ep.Category.FOODS: Icons.fastfood_outlined,
    ep.Category.ACTIVITIES: Icons.sports_soccer,
    ep.Category.TRAVEL: Icons.directions_car_outlined,
    ep.Category.OBJECTS: Icons.lightbulb_outline,
    ep.Category.SYMBOLS: Icons.emoji_symbols_outlined,
    ep.Category.FLAGS: Icons.flag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < categories.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected ? Wa.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Icon(
                    _icons[categories[i].category] ?? Icons.circle_outlined,
                    size: 20,
                    color: i == selected ? Wa.accent : Thread.meta,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
