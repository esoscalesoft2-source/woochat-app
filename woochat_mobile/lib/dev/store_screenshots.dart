import 'package:flutter/material.dart';

import '../src/core/constants.dart';
import '../src/core/formatting.dart';
import '../src/features/chat/widgets/message_bubble.dart';
import '../src/features/chat/widgets/message_composer.dart';
import '../src/features/chats/widgets/chat_list_tile.dart';
import '../src/features/chats/widgets/contact_avatar.dart';
import '../src/features/chats/widgets/owner_view_pills.dart';
import '../src/features/chats/widgets/schedules_chip.dart';
import '../src/features/shell/home_nav_bar.dart';
import '../src/models/chat.dart';
import '../src/models/chat_attention.dart';
import '../src/models/message.dart';
import '../src/theme/app_theme.dart';
import '../src/theme/wa_colors.dart';

/// Dev-only entry point: the real chat list and thread widgets over made-up
/// customers, for store screenshots that show no one's real conversations.
/// Swipe sideways between the screens.
///
///   flutter run -t lib/dev/store_screenshots.dart
void main() => runApp(const _StoreShots());

const String _me = 'me';
final DateTime _now = DateTime.now();
DateTime _ago(int minutes) => _now.subtract(Duration(minutes: minutes));

class _Row {
  const _Row(
    this.name,
    this.phone,
    this.last,
    this.minutesAgo, {
    this.unread = 0,
    this.owner = 'Divya',
    this.labels = const <String>[],
    this.product,
    this.note,
    this.mine = false,
    this.outbound = false,
    this.pinned = false,
  });

  final String name;
  final String phone;
  final String last;
  final int minutesAgo;
  final int unread;
  final String owner;
  final List<String> labels;
  final String? product;
  final String? note;
  final bool mine;
  final bool outbound;
  final bool pinned;

  Chat get chat => Chat.fromMap(<String, dynamic>{
    'id': name,
    'user_id': 'owner',
    'contact_name': name,
    'contact_phone': phone,
    'is_pinned': pinned,
    'is_unread': unread > 0,
    'unread_count': unread,
    'last_message': last,
    'last_message_at': _ago(minutesAgo).toIso8601String(),
    'last_message_direction': outbound
        ? MessageDirection.outbound
        : MessageDirection.inbound,
    'last_message_status': outbound ? MessageStatus.read : null,
    'assigned_to': mine ? _me : 'someone',
  });
}

// Made-up customers of a made-up clothing store.
const List<_Row> _rows = <_Row>[
  _Row(
    'Priya Sharma',
    '+91 98765 43210',
    'Is the blue kurti available in M size?',
    2,
    unread: 2,
    owner: 'You',
    labels: <String>['#22C55E'],
    product: 'Cotton Kurti',
    mine: true,
  ),
  _Row(
    'Ravi Textiles',
    '+91 90031 22045',
    'Order confirmed. Thank you! 🙏',
    9,
    owner: 'Arun',
    outbound: true,
    pinned: true,
  ),
  _Row(
    'Meena Boutique',
    '+91 94440 56781',
    'Can you send the price list?',
    14,
    unread: 1,
    owner: 'You',
    labels: <String>['#F59E0B'],
    note: 'Wholesale buyer, 50+ pieces',
    mine: true,
  ),
  _Row(
    'Karthik R',
    '+91 99620 11873',
    '🎤 Voice message',
    31,
    owner: 'Divya',
    product: 'Track Pants',
  ),
  _Row(
    'Anitha Stores',
    '+91 97899 30412',
    'Delivery by Friday is perfect',
    58,
    owner: 'Arun',
    outbound: true,
    labels: <String>['#3B82F6'],
  ),
  _Row(
    'Suresh Kumar',
    '+91 93821 77654',
    'Do you have the black one in XL?',
    80,
    unread: 3,
    owner: 'You',
    product: 'Oversized T-Shirt',
    mine: true,
  ),
  _Row('Lakshmi Fashions', '+91 98410 66290', '📷 Photo', 120, owner: 'Divya'),
];

class _StoreShots extends StatelessWidget {
  const _StoreShots();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: PageView(
        children: const <Widget>[
          _ChatList(view: OwnerView.all),
          _ChatList(view: OwnerView.mine),
          _Thread(),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.view});

  final OwnerView view;

  @override
  Widget build(BuildContext context) {
    final rows = view == OwnerView.mine
        ? _rows.where((row) => row.mine).toList()
        : _rows;
    return Scaffold(
      backgroundColor: Wa.background,
      bottomNavigationBar: const HomeNavBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Wa.accent,
        foregroundColor: Wa.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_comment, size: 24),
      ),
      body: Column(
        children: <Widget>[
          _Header(view: view),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final (index, row) in rows.indexed)
                  ChatListTile(
                    chat: row.chat,
                    subtitleStamp: TimeFormat.listStamp(row.chat.lastMessageAt),
                    showDivider: index != rows.length - 1,
                    labelColors: row.labels,
                    ownerLine: OwnerLine(OwnerLineKind.assignee, row.owner),
                    productName: row.product,
                    noteExcerpt: row.note,
                    needsYou: row.mine,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chat list's header as the app draws it: wordmark, search, pills, chips.
class _Header extends StatelessWidget {
  const _Header({required this.view});

  final OwnerView view;

  @override
  Widget build(BuildContext context) {
    final mine = _rows.where((row) => row.mine).length;
    final unread = _rows.where((row) => row.unread > 0).length;
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Wa.divider, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: <Widget>[
                  Image.asset('assets/branding/app-logo.png', height: 34),
                  const Spacer(),
                  for (final icon in <IconData>[
                    Icons.people_outline,
                    Icons.refresh,
                    Icons.settings_outlined,
                  ])
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(icon, size: 22, color: Wa.icon),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Wa.chipInactiveBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.search, size: 18, color: Wa.secondaryText),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Search or start new chat',
                        style: TextStyle(color: Wa.secondaryText, fontSize: 14),
                      ),
                    ),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 17,
                      color: Wa.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OwnerViewPills(
                  view: view,
                  counts: <OwnerView, int>{
                    OwnerView.mine: mine,
                    OwnerView.bot: 12,
                  },
                  onChanged: (_) {},
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                children: <Widget>[
                  _Chip(label: 'All (${_rows.length})', active: true),
                  const SizedBox(width: 6),
                  _Chip(label: 'Unread ($unread)'),
                  const SizedBox(width: 6),
                  SchedulesChip(bucket: null, hasPending: true, onTap: () {}),
                  const SizedBox(width: 6),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Wa.chipInactiveBackground,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Wa.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? Wa.chipActiveBackground : Wa.chipInactiveBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: active ? Colors.white : Wa.secondaryText,
        ),
      ),
    );
  }
}

/// One made-up conversation, in the real bubbles and composer.
class _Thread extends StatelessWidget {
  const _Thread();

  @override
  Widget build(BuildContext context) {
    final chat = _rows.first.chat;
    Message m(int id, String body, int minutesAgo, {bool out = false}) =>
        Message(
          id: '$id',
          chatId: chat.id,
          userId: _me,
          direction: out ? MessageDirection.outbound : MessageDirection.inbound,
          content: body,
          status: out ? MessageStatus.read : null,
          createdAt: _ago(minutesAgo),
        );

    final messages = <Message>[
      m(1, 'Hi! I saw your Instagram post 😊', 26),
      m(2, 'Is the blue kurti available in M size?', 25),
      m(
        3,
        'Hi Priya! Yes, the blue cotton kurti is in stock in S, M and L 👗',
        22,
        out: true,
      ),
      m(4, 'Price is ₹799, with free delivery in Chennai.', 22, out: true),
      m(
        5,
        '[attachment:audio|voice-note.m4a|https%3A%2F%2Fexample.invalid%2Fv.m4a]',
        12,
      ),
      m(6, 'Can I pay on delivery?', 3),
      m(7, 'Of course! Shall I book one M size for you?', 2, out: true),
    ];

    return Scaffold(
      backgroundColor: Thread.background,
      appBar: AppBar(
        backgroundColor: Thread.composer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: Wa.icon),
        leading: const Icon(Icons.arrow_back_ios_new, size: 20),
        title: Row(
          children: <Widget>[
            ContactAvatar(chat: chat, radius: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    chat.displayName,
                    style: const TextStyle(
                      color: Thread.text,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    chat.shownPhone,
                    style: const TextStyle(color: Thread.meta, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: const <Widget>[
          Icon(Icons.call_outlined),
          SizedBox(width: 18),
          Icon(Icons.search),
          SizedBox(width: 14),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ThreadBackground(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: <Widget>[
                  DayDivider(day: _now),
                  for (final (index, message) in messages.indexed)
                    MessageBubble(
                      message: message,
                      autoLoadMedia: false,
                      showTail:
                          index == 0 ||
                          messages[index - 1].direction != message.direction,
                    ),
                ],
              ),
            ),
          ),
          MessageComposer(
            onSend: (_) async => false,
            windowOpen: true,
            onTemplates: () {},
            onAttach: (_) {},
            onSchedule: (_, _, _) async => false,
            onBlocked: () {},
            onVoiceNote: (_) async => false,
            onRecorderProblem: (_) {},
            lastInboundAt: _ago(3),
          ),
        ],
      ),
    );
  }
}
