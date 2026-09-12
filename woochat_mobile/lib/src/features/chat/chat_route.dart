import 'package:flutter/material.dart';

import '../../data/chats_repository.dart';
import '../../models/chat.dart';
import '../../state/session_scope.dart';
import 'chat_screen.dart';

/// `/chats/:chatId`.
///
/// Opening from the list passes the [Chat] along so the conversation renders
/// immediately. A deep link or a page reload has no object to pass, so the row
/// is fetched by id first.
class ChatRoute extends StatefulWidget {
  const ChatRoute({super.key, required this.chatId, this.initialChat});

  final String chatId;
  final Chat? initialChat;

  @override
  State<ChatRoute> createState() => _ChatRouteState();
}

class _ChatRouteState extends State<ChatRoute> {
  final _repository = const ChatsRepository();

  Chat? _chat;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.initialChat;
    if (_chat == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final chat = await _repository.fetchChat(widget.chatId);
      if (!mounted) return;
      setState(() {
        _chat = chat;
        _error = chat == null ? 'This conversation could not be found.' : null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open the chat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantContext = SessionScope.of(context).tenantContext;
    final chat = _chat;

    if (chat != null && tenantContext != null) {
      return ChatScreen(chat: chat, tenantContext: tenantContext);
    }

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _loading || _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
