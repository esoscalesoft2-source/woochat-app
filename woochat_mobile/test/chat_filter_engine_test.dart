import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/chat_filter_state.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

Chat chat(
  String id, {
  String phone = '',
  bool archived = false,
  int unread = 0,
  bool isUnread = false,
  DateTime? lastMessageAt,
  String? automationId,
  DateTime? automationTriggeredAt,
  String? adHeadline,
}) =>
    Chat(
      id: id,
      userId: 'tenant',
      contactName: id,
      contactPhone: phone,
      isArchived: archived,
      unreadCount: unread,
      isUnread: isUnread,
      lastMessageAt: lastMessageAt,
      lastAutomationId: automationId,
      lastAutomationTriggeredAt: automationTriggeredAt,
      lastAdHeadline: adHeadline,
    );

List<String> idsOf(List<Chat> chats) => chats.map((c) => c.id).toList();

List<Chat> run(
  List<Chat> chats,
  ChatFilterState state, {
  ChatFilterData data = ChatFilterData.empty,
  DateTimeRangeMs? range,
  Set<String>? scheduleIds,
}) =>
    ChatFilterEngine.apply(
      chats: chats,
      data: data,
      state: state,
      range: range,
      scheduleIds: scheduleIds,
    );

void main() {
  group('tabs', () {
    final chats = <Chat>[
      chat('open'),
      chat('archived', archived: true),
      chat('unread', unread: 3),
      // is_unread without a counter must NOT count as unread, matching the web.
      chat('flagged-only', isUnread: true),
    ];

    test('All hides archived chats', () {
      final result = run(chats, ChatFilterState.initial);
      expect(idsOf(result), <String>['open', 'unread', 'flagged-only']);
    });

    test('Unread counts unread_count only', () {
      final result = run(
        chats,
        ChatFilterState.initial.selectTab(ContactTab.unread),
      );
      expect(idsOf(result), <String>['unread']);
    });

    test('Archived shows only archived', () {
      final result = run(chats, ChatFilterState.initial.selectArchived());
      expect(idsOf(result), <String>['archived']);
    });
  });

  group('labels', () {
    // The same name under two ids, as a Contacts import creates.
    const data = ChatFilterData(
      labels: <Label>[
        Label(id: 'l1', name: 'Hot Lead'),
        Label(id: 'l2', name: 'hot lead'),
        Label(id: 'l3', name: 'Cold'),
      ],
      labelIdsByChat: <String, List<String>>{
        'a': <String>['l1'],
        'b': <String>['l2'],
        'c': <String>['l3'],
      },
    );

    test('matches every label id sharing the selected name', () {
      final result = run(
        <Chat>[chat('a'), chat('b'), chat('c')],
        ChatFilterState.initial.selectLabel('l1'),
        data: data,
      );
      // 'b' holds the duplicate id and must not be missed.
      expect(idsOf(result), <String>['a', 'b']);
    });

    test('UnAssigned means no label from either source', () {
      const withContactLabel = ChatFilterData(
        labels: <Label>[Label(id: 'l1', name: 'Hot')],
        labelIdsByChat: <String, List<String>>{'a': <String>['l1']},
        contactLabelIdsByPhone: <String, List<String>>{
          '919': <String>['l1'],
        },
      );

      final result = run(
        <Chat>[chat('a'), chat('b', phone: '+91 9'), chat('c')],
        ChatFilterState.initial.selectLabel(FilterSentinel.unassignedLabel),
        data: withContactLabel,
      );
      // 'b' carries the label on its contact record, so it is not unassigned.
      expect(idsOf(result), <String>['c']);
    });
  });

  group('date range', () {
    final inside = DateTime(2026, 6, 15);
    final outside = DateTime(2026, 1, 1);
    final range = DateTimeRangeMs(
      DateTime(2026, 6, 1).millisecondsSinceEpoch,
      DateTime(2026, 6, 30).millisecondsSinceEpoch,
    );

    test('filters on last_message_at when no label is selected', () {
      final result = run(
        <Chat>[
          chat('recent', lastMessageAt: inside),
          chat('old', lastMessageAt: outside),
        ],
        ChatFilterState.initial,
        range: range,
      );
      expect(idsOf(result), <String>['recent']);
    });

    test('switches to the label-assigned date when a label is selected', () {
      final data = ChatFilterData(
        labels: const <Label>[Label(id: 'l1', name: 'Hot')],
        labelIdsByChat: const <String, List<String>>{
          'a': <String>['l1'],
          'b': <String>['l1'],
        },
        labelAppliedAt: <String, DateTime>{
          // Labelled inside the range, but last spoke long before it.
          'a:l1': inside,
          // Chatted inside the range, but labelled outside it.
          'b:l1': outside,
        },
      );

      final result = run(
        <Chat>[
          chat('a', lastMessageAt: outside),
          chat('b', lastMessageAt: inside),
        ],
        ChatFilterState.initial.selectLabel('l1'),
        data: data,
        range: range,
      );

      expect(idsOf(result), <String>['a']);
    });

    test('any assignment inside the range is enough', () {
      final data = ChatFilterData(
        labels: const <Label>[
          Label(id: 'l1', name: 'Hot'),
          Label(id: 'l2', name: 'hot'),
        ],
        labelIdsByChat: const <String, List<String>>{
          'a': <String>['l1', 'l2'],
        },
        labelAppliedAt: <String, DateTime>{
          'a:l1': outside,
          'a:l2': inside,
        },
      );

      final result = run(
        <Chat>[chat('a')],
        ChatFilterState.initial.selectLabel('l1'),
        data: data,
        range: range,
      );
      expect(idsOf(result), <String>['a']);
    });
  });

  group('categories', () {
    const data = ChatFilterData(
      labels: <Label>[Label(id: 'l1', name: 'Hot')],
      labelIdsByChat: <String, List<String>>{
        'a': <String>['l1'],
        'b': <String>['l1'],
      },
      categories: <Category>[Category(id: 'c1', name: 'Retail')],
      categoryIdsByChat: <String, List<String>>{
        'a': <String>['c1'],
      },
    );

    test('ANDs with the label filter rather than replacing it', () {
      final state =
          ChatFilterState.initial.selectLabel('l1').selectCategory('c1');
      final result = run(<Chat>[chat('a'), chat('b')], state, data: data);
      expect(idsOf(result), <String>['a']);
    });

    test('UnAssigned finds chats with no category', () {
      final result = run(
        <Chat>[chat('a'), chat('b')],
        ChatFilterState.initial
            .selectCategory(FilterSentinel.unassignedCategory),
        data: data,
      );
      expect(idsOf(result), <String>['b']);
    });
  });

  group('products', () {
    const data = ChatFilterData(
      products: <Product>[
        Product(id: 'p1', title: 'Camp'),
        Product(id: 'p2', title: 'Coaching'),
      ],
      collectionProductIdByPhone: <String, String>{'911': 'p1'},
      productIdByAdHeadline: <String, String>{
        'Fitness Ad': 'p2',
        'Foreign Ad': 'p-other-tenant',
      },
    );

    test('a hand-picked collection wins over the ad it arrived on', () {
      final result = run(
        <Chat>[chat('a', phone: '+91 1', adHeadline: 'Fitness Ad')],
        ChatFilterState.initial.selectProduct('p1'),
        data: data,
      );
      expect(idsOf(result), <String>['a']);
    });

    test('falls back to the ad headline when there is no collection', () {
      final result = run(
        <Chat>[chat('b', adHeadline: 'Fitness Ad')],
        ChatFilterState.initial.selectProduct('p2'),
        data: data,
      );
      expect(idsOf(result), <String>['b']);
    });

    test('a product the tenant cannot see resolves to UnAssigned', () {
      final result = run(
        <Chat>[chat('c', adHeadline: 'Foreign Ad'), chat('d')],
        ChatFilterState.initial
            .selectProduct(FilterSentinel.unassignedProduct),
        data: data,
      );
      expect(idsOf(result), <String>['c', 'd']);
    });
  });

  group('lead source', () {
    const data = ChatFilterData(adSourcedChatIds: <String>{'a'});

    test('splits Meta Ads from Organic', () {
      final ads = run(
        <Chat>[chat('a'), chat('b')],
        ChatFilterState.initial.selectSource(LeadSource.ads),
        data: data,
      );
      final organic = run(
        <Chat>[chat('a'), chat('b')],
        ChatFilterState.initial.selectSource(LeadSource.organic),
        data: data,
      );

      expect(idsOf(ads), <String>['a']);
      expect(idsOf(organic), <String>['b']);
    });
  });

  group('auto reply', () {
    final triggered = DateTime(2026, 6, 1);
    const data = ChatFilterData(funnelReplied: <String>{'r'});

    test('All Automations needs a trigger AND is_unread', () {
      final result = run(
        <Chat>[
          chat('both', automationTriggeredAt: triggered, isUnread: true),
          chat('read-only', automationTriggeredAt: triggered),
          chat('never', isUnread: true),
        ],
        ChatFilterState.initial
            .selectAutomation(FilterSentinel.automationAll),
        data: data,
      );
      expect(idsOf(result), <String>['both']);
    });

    test('Replied uses the funnel RPC set', () {
      final result = run(
        <Chat>[chat('r'), chat('x')],
        ChatFilterState.initial
            .selectAutomation(FilterSentinel.automationReplied),
        data: data,
      );
      expect(idsOf(result), <String>['r']);
    });

    test('a specific automation matches last_automation_id', () {
      final result = run(
        <Chat>[chat('a', automationId: 'auto-1'), chat('b')],
        ChatFilterState.initial.selectAutomation('auto-1'),
      );
      expect(idsOf(result), <String>['a']);
    });
  });

  group('funnel failed and notes', () {
    const data = ChatFilterData(
      funnelFailed: <String>{'f'},
      contactIdByPhone: <String, String>{'911': 'contact-1'},
      notesByContactId: <String, List<Note>>{
        'contact-1': <Note>[
          Note(id: 'n1', text: 'Wants a REFUND', tags: <String>['billing']),
        ],
      },
    );

    test('funnel failed keeps only undelivered chats', () {
      final result = run(
        <Chat>[chat('f'), chat('g')],
        ChatFilterState.initial.toggleFunnelFailed(),
        data: data,
      );
      expect(idsOf(result), <String>['f']);
    });

    test('note keyword matches text case-insensitively', () {
      final result = run(
        <Chat>[chat('a', phone: '+91 1'), chat('b')],
        ChatFilterState.initial.applyNoteKeyword('refund'),
        data: data,
      );
      expect(idsOf(result), <String>['a']);
    });

    test('note keyword also matches a tag', () {
      final result = run(
        <Chat>[chat('a', phone: '+91 1'), chat('b')],
        ChatFilterState.initial.applyNoteKeyword('bill'),
        data: data,
      );
      expect(idsOf(result), <String>['a']);
    });

    test('tag filter matches exactly, not as a substring', () {
      final match = run(
        <Chat>[chat('a', phone: '+91 1')],
        ChatFilterState.initial.selectNoteTag('BILLING'),
        data: data,
      );
      final noMatch = run(
        <Chat>[chat('a', phone: '+91 1')],
        ChatFilterState.initial.selectNoteTag('bill'),
        data: data,
      );

      expect(idsOf(match), <String>['a']);
      expect(noMatch, isEmpty);
    });
  });

  group('clear-lists differ per button', () {
    // The axes that survive almost every button.
    final sticky = ChatFilterState.initial
        .selectCategory('c1')
        .selectProduct('p1')
        .selectSource(LeadSource.ads);

    void expectStickyKept(ChatFilterState state) {
      expect(state.categoryId, 'c1');
      expect(state.productId, 'p1');
      expect(state.source, LeadSource.ads);
    }

    test('Archived clears label, automation and notes only', () {
      // Label, automation and notes are mutually exclusive by design, so each
      // is asserted from its own starting state.
      final fromLabel = sticky.selectLabel('l1').selectArchived();
      final fromAutomation = sticky.selectAutomation('auto-1').selectArchived();
      final fromNotes = sticky.applyNoteKeyword('refund').selectArchived();

      expect(fromLabel.tab, ContactTab.archived);
      expect(fromLabel.labelId, isNull);
      expect(fromAutomation.automationId, isNull);
      expect(fromNotes.hasNoteFilter, isFalse);
      expectStickyKept(fromLabel);
      expectStickyKept(fromAutomation);
    });

    test('Funnel failed keeps the automation filter', () {
      final state = sticky.selectAutomation('auto-1').toggleFunnelFailed();

      expect(state.funnelFailed, isTrue);
      expect(state.tab, ContactTab.all);
      expect(state.labelId, isNull);
      expect(state.hasNoteFilter, isFalse);
      // Explicitly NOT cleared, unlike every other button.
      expect(state.automationId, 'auto-1');
      expectStickyKept(state);
    });

    test('Label clears automation and notes', () {
      final state = sticky.selectAutomation('auto-1').selectLabel('l9');

      expect(state.labelId, 'l9');
      expect(state.automationId, isNull);
      expect(state.hasNoteFilter, isFalse);
      expectStickyKept(state);
    });

    test('Auto Reply clears label and notes but not category or product', () {
      final state = sticky.selectLabel('l1').selectAutomation('auto-2');

      expect(state.automationId, 'auto-2');
      expect(state.labelId, isNull);
      expect(state.hasNoteFilter, isFalse);
      expectStickyKept(state);
    });

    test('Auto Reply "Clear Filter" also drops the funnel toggle', () {
      final state = sticky.toggleFunnelFailed().selectAutomation(null);

      expect(state.automationId, isNull);
      expect(state.funnelFailed, isFalse);
    });

    test('Category and Product clear nothing', () {
      final state = ChatFilterState.initial
          .selectLabel('l1')
          .selectSource(LeadSource.ads)
          .selectCategory('c2')
          .selectProduct('p2');

      expect(state.labelId, 'l1');
      expect(state.source, LeadSource.ads);
      expect(state.categoryId, 'c2');
      expect(state.productId, 'p2');
    });

    test('Notes clears label and automation', () {
      final fromLabel = sticky.selectLabel('l1').selectNoteTag('billing');
      final fromAutomation =
          sticky.selectAutomation('auto-1').selectNoteTag('billing');

      expect(fromLabel.noteTag, 'billing');
      expect(fromLabel.noteKeyword, isEmpty);
      expect(fromLabel.labelId, isNull);
      expect(fromAutomation.automationId, isNull);
      expectStickyKept(fromLabel);
    });

    test('applying a note keyword clears the label', () {
      final state = sticky.selectLabel('l1').applyNoteKeyword('refund');

      expect(state.noteKeyword, 'refund');
      expect(state.labelId, isNull);
    });
  });
}
