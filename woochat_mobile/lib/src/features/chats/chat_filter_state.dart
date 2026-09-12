import '../../models/chat.dart';
import '../../models/chat_filters.dart';

/// Sentinels shared with the web app so both read the same values.
class FilterSentinel {
  const FilterSentinel._();
  static const String unassignedLabel = '__unassigned__';
  static const String unassignedCategory = '__no_cat__';
  static const String unassignedProduct = '__no_product__';
  static const String automationReplied = '__replied__';
  static const String automationAll = 'all';
}

/// The three mutually exclusive tabs. "All" always hides archived chats —
/// only the Archived tab shows them, or every count is wrong.
enum ContactTab { all, unread, archived }

enum LeadSource { ads, organic }

/// Everything the chats list is currently narrowed by.
///
/// Transitions are methods rather than raw copies because selecting one filter
/// clears a *different* set of others depending on which button was pressed.
class ChatFilterState {
  const ChatFilterState({
    this.tab = ContactTab.all,
    this.labelId,
    this.categoryId,
    this.productId,
    this.source,
    this.automationId,
    this.funnelFailed = false,
    this.noteKeyword = '',
    this.noteTag,
    this.ownerId,
  });

  final ContactTab tab;
  final String? labelId;
  final String? categoryId;
  final String? productId;
  final LeadSource? source;
  final String? automationId;
  final bool funnelFailed;
  final String noteKeyword;
  final String? noteTag;

  /// `chats.user_id` — which team member's conversations to show.
  final String? ownerId;

  static const ChatFilterState initial = ChatFilterState();

  bool get hasNoteFilter => noteTag != null || noteKeyword.trim().isNotEmpty;

  /// True when anything beyond the plain All tab is narrowing the list.
  bool get isNarrowed =>
      tab != ContactTab.all ||
      labelId != null ||
      categoryId != null ||
      productId != null ||
      source != null ||
      automationId != null ||
      funnelFailed ||
      hasNoteFilter ||
      ownerId != null;

  /// The date range applies to when a label went on, not to last activity,
  /// whenever a specific label is selected.
  bool get datesLabelAssignment =>
      labelId != null && labelId != FilterSentinel.unassignedLabel;

  ChatFilterState _copy({
    ContactTab? tab,
    Object? labelId = _keep,
    Object? categoryId = _keep,
    Object? productId = _keep,
    Object? source = _keep,
    Object? automationId = _keep,
    bool? funnelFailed,
    String? noteKeyword,
    Object? noteTag = _keep,
    Object? ownerId = _keep,
  }) {
    return ChatFilterState(
      tab: tab ?? this.tab,
      labelId: labelId == _keep ? this.labelId : labelId as String?,
      categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
      productId: productId == _keep ? this.productId : productId as String?,
      source: source == _keep ? this.source : source as LeadSource?,
      automationId:
          automationId == _keep ? this.automationId : automationId as String?,
      funnelFailed: funnelFailed ?? this.funnelFailed,
      noteKeyword: noteKeyword ?? this.noteKeyword,
      noteTag: noteTag == _keep ? this.noteTag : noteTag as String?,
      ownerId: ownerId == _keep ? this.ownerId : ownerId as String?,
    );
  }

  static const Object _keep = Object();

  // --- Transitions. The clear-lists differ per button; these mirror the web
  // app's handlers exactly rather than sharing one generic reset. ---

  /// Primary tabs. Selecting All or Unread leaves the dropdown filters alone.
  ChatFilterState selectTab(ContactTab next) => _copy(tab: next);

  /// Archived clears label, automation and note filters — but not the date
  /// range, category, product, lead source or funnel toggle.
  ChatFilterState selectArchived() => _copy(
        tab: ContactTab.archived,
        labelId: null,
        automationId: null,
        noteKeyword: '',
        noteTag: null,
      );

  /// Funnel failed toggles, returns to the All tab and clears label + notes.
  /// It deliberately leaves the automation filter in place.
  ChatFilterState toggleFunnelFailed() => _copy(
        funnelFailed: !funnelFailed,
        tab: ContactTab.all,
        labelId: null,
        noteKeyword: '',
        noteTag: null,
      );

  /// Choosing a label clears automation and notes, and returns to All.
  ChatFilterState selectLabel(String? id) {
    if (id == null) {
      // "All Labels" only clears the note filters.
      return _copy(labelId: null, noteKeyword: '', noteTag: null);
    }
    return _copy(
      labelId: id,
      tab: ContactTab.all,
      automationId: null,
      noteKeyword: '',
      noteTag: null,
    );
  }

  /// Category is an independent axis — it ANDs with the label filter and
  /// clears nothing.
  ChatFilterState selectCategory(String? id) => _copy(categoryId: id);

  /// Product clears nothing either.
  ChatFilterState selectProduct(String? id) => _copy(productId: id);

  /// Lead source returns to the All tab and clears nothing else.
  ChatFilterState selectSource(LeadSource? next) => next == null
      ? _copy(source: null)
      : _copy(source: next, tab: ContactTab.all);

  /// Auto Reply clears label and notes but keeps the date range, because
  /// "Replied" is scoped by that very range.
  ChatFilterState selectAutomation(String? id) {
    if (id == null) {
      // "Clear Filter" also drops the funnel toggle.
      return _copy(
        automationId: null,
        noteKeyword: '',
        noteTag: null,
        funnelFailed: false,
      );
    }
    return _copy(
      automationId: id,
      tab: ContactTab.all,
      labelId: null,
      noteKeyword: '',
      noteTag: null,
    );
  }

  /// Applying a note keyword clears label and automation.
  ChatFilterState applyNoteKeyword(String keyword) => _copy(
        noteKeyword: keyword.trim(),
        tab: ContactTab.all,
        labelId: null,
        automationId: null,
      );

  /// Picking a tag clears the keyword, label and automation.
  ChatFilterState selectNoteTag(String tag) => _copy(
        noteTag: tag,
        noteKeyword: '',
        tab: ContactTab.all,
        labelId: null,
        automationId: null,
      );

  ChatFilterState clearNoteFilters() => _copy(noteKeyword: '', noteTag: null);

  /// Team-user filter. Independent axis -- it clears nothing.
  ChatFilterState selectOwner(String? id) => _copy(ownerId: id);

  /// Clears every dropdown filter, leaving the tab and date range alone.
  ChatFilterState clearAll() => _copy(
        labelId: null,
        categoryId: null,
        productId: null,
        source: null,
        automationId: null,
        funnelFailed: false,
        noteKeyword: '',
        noteTag: null,
        ownerId: null,
      );
}

/// Applies [ChatFilterState] to an in-memory chat list.
///
/// The order mirrors the web app so both produce the same list.
class ChatFilterEngine {
  const ChatFilterEngine._();

  static List<Chat> apply({
    required List<Chat> chats,
    required ChatFilterData data,
    required ChatFilterState state,
    DateTimeRangeMs? range,
    Set<String>? scheduleIds,
  }) {
    var result = chats;

    // Team user — whose conversations these are (`chats.user_id`).
    final ownerId = state.ownerId;
    if (ownerId != null) {
      result = result.where((chat) => chat.userId == ownerId).toList();
    }

    // Date range — by last activity, unless a label is picked, in which case
    // it applies to when that label went on instead.
    if (range != null && !state.datesLabelAssignment) {
      result = result.where((chat) {
        final at = chat.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        return at >= range.start && at <= range.end;
      }).toList();
    }

    // Tab. "All" hides archived.
    result = switch (state.tab) {
      ContactTab.unread =>
        result.where((chat) => chat.unreadCount > 0).toList(),
      ContactTab.archived => result.where((chat) => chat.isArchived).toList(),
      ContactTab.all => result.where((chat) => !chat.isArchived).toList(),
    };

    // Label — matched by every id sharing the selected label's name.
    final labelId = state.labelId;
    if (labelId == FilterSentinel.unassignedLabel) {
      result = result
          .where((chat) =>
              data.labelIdsForChat(chat.id, chat.normalisedPhone).isEmpty)
          .toList();
    } else if (labelId != null) {
      final ids = data.idsSharingNameWith(labelId);
      result = result.where((chat) {
        final held = data.labelIdsForChat(chat.id, chat.normalisedPhone);
        return held.any(ids.contains) &&
            data.labelAppliedInRange(chat.id, ids, range);
      }).toList();
    }

    // Category — independent axis, ANDed with the label above.
    final categoryId = state.categoryId;
    if (categoryId == FilterSentinel.unassignedCategory) {
      result = result
          .where((chat) => (data.categoryIdsByChat[chat.id] ?? const <String>[])
              .isEmpty)
          .toList();
    } else if (categoryId != null) {
      result = result
          .where((chat) => (data.categoryIdsByChat[chat.id] ?? const <String>[])
              .contains(categoryId))
          .toList();
    }

    // Lead source.
    final source = state.source;
    if (source != null) {
      result = result.where((chat) {
        final fromAds = data.adSourcedChatIds.contains(chat.id);
        return source == LeadSource.ads ? fromAds : !fromAds;
      }).toList();
    }

    if (scheduleIds != null) {
      result = result.where((chat) => scheduleIds.contains(chat.id)).toList();
    }

    // Product.
    final productId = state.productId;
    if (productId == FilterSentinel.unassignedProduct) {
      result = result.where((chat) => _productFor(data, chat) == null).toList();
    } else if (productId != null) {
      result = result
          .where((chat) => _productFor(data, chat) == productId)
          .toList();
    }

    // Auto Reply.
    final automationId = state.automationId;
    if (automationId == FilterSentinel.automationAll) {
      result = result
          .where((chat) => chat.lastAutomationTriggeredAt != null && chat.isUnread)
          .toList();
    } else if (automationId == FilterSentinel.automationReplied) {
      result = result
          .where((chat) => data.funnelReplied.contains(chat.id))
          .toList();
    } else if (automationId != null) {
      result = result
          .where((chat) => chat.lastAutomationId == automationId)
          .toList();
    }

    // Funnel messages that never arrived.
    if (state.funnelFailed) {
      result =
          result.where((chat) => data.funnelFailed.contains(chat.id)).toList();
    }

    // Notes, matched against the customer's contact record.
    if (state.hasNoteFilter) {
      final keyword = state.noteKeyword.trim().toLowerCase();
      final tag = state.noteTag;
      result = result.where((chat) {
        final contactId = data.contactIdByPhone[chat.normalisedPhone];
        final notes = contactId == null
            ? const <Note>[]
            : data.notesByContactId[contactId] ?? const <Note>[];
        return notes.any((note) {
          final tagOk = tag == null ||
              note.tags.any((t) => t.toLowerCase() == tag.toLowerCase());
          final keywordOk = keyword.isEmpty ||
              (note.text ?? '').toLowerCase().contains(keyword) ||
              note.tags.any((t) => t.toLowerCase().contains(keyword));
          return tagOk && keywordOk;
        });
      }).toList();
    }

    return result;
  }

  static String? _productFor(ChatFilterData data, Chat chat) =>
      data.productIdForChat(chat.normalisedPhone, chat.lastAdHeadline);

  /// Count for one dropdown option, over the already search/date-scoped list.
  static int count({
    required List<Chat> chats,
    required ChatFilterData data,
    required ChatFilterState state,
    DateTimeRangeMs? range,
  }) =>
      apply(chats: chats, data: data, state: state, range: range).length;
}
