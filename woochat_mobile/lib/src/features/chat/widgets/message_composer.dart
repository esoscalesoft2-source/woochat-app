import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';
import 'attach_menu.dart';
import 'emoji_picker.dart';
import 'quick_replies_panel.dart';
import 'schedule_message_sheet.dart';
import 'voice_recorder.dart';

/// The single-line height of the input bar. The field is padded to exactly
/// this, and every button in the bar is boxed to it, so they line up.
const double kComposerRowHeight = 46;

/// Shown whenever the closed window refuses something. Same wording as the web.
const String kWindowClosedMessage =
    "The 24-hour window has expired — tap the 'Templates' option to send an "
    'approved template message.';

/// Shown when the microphone was refused, which only the user can undo.
const String kMicrophoneDeniedMessage =
    'Microphone access was refused. Allow it for this app, then tap the '
    'mic again.';

/// Splices [emoji] into [text] at [selection], returning the new text and
/// where the caret should land. Pulled out of the widget so the caret handling
/// can be tested without driving the emoji grid.
(String text, int caret) spliceEmoji(
  String text,
  TextSelection selection,
  String emoji,
) {
  // An unset selection means the field was never focused, so append.
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : start;
  return (text.replaceRange(start, end, emoji), start + emoji.length);
}

/// The message input bar: `+`, emoji, field, schedule, mic — one thin row.
///
/// The bar is always present. When the 24-hour window has closed, free-form
/// composing is refused rather than the bar being taken away, which is what
/// the web app does: the notice reappears on whatever was just refused.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    required this.windowOpen,
    required this.onTemplates,
    required this.onAttach,
    required this.onSchedule,
    required this.onBlocked,
    required this.onVoiceNote,
    required this.onRecorderProblem,
    this.loadQuickReplies,
    this.onCreateQuickReply,
    this.noticeHidden = false,
    this.onDismissNotice,
    this.emojiPickerBuilder,
    this.recorderBuilder,
  });

  /// Loads the saved replies behind `/`. Called once, the first time a slash
  /// is typed, so opening a chat costs nothing.
  final Future<List<QuickReply>> Function()? loadQuickReplies;

  /// Opens the New quick reply sheet and returns what was saved, or null if
  /// it was dismissed. Without it the option is reported through [onAttach].
  final Future<QuickReply?> Function()? onCreateQuickReply;

  /// Overrides the emoji panel. Only tests use this — the real picker loads
  /// its emoji set through a platform channel that never settles under
  /// `pumpAndSettle`, which would leave every composer test hanging.
  final Widget Function(ValueChanged<String> onPick)? emojiPickerBuilder;

  /// Returns true when the message was accepted, so the field can be cleared.
  final Future<bool> Function(String text) onSend;

  /// False once 24 hours have passed since the contact's last inbound message.
  final bool windowOpen;

  final VoidCallback onTemplates;

  /// Uploads and sends a finished recording. Returns true once it is away.
  final Future<bool> Function(VoiceClip clip) onVoiceNote;

  /// A refused microphone, or a recorder that would not start.
  final ValueChanged<String> onRecorderProblem;

  /// Overrides the recorder. Only tests use this — the real one needs a
  /// microphone and a platform channel.
  final VoiceRecorder Function()? recorderBuilder;

  /// An attach option other than Template Message.
  final ValueChanged<AttachOption> onAttach;

  /// A moment picked in the Schedule dialog.
  final ValueChanged<ScheduledSend> onSchedule;

  /// Something the closed window refused — typing, emoji, an attachment.
  final VoidCallback onBlocked;

  final bool noticeHidden;
  final VoidCallback? onDismissNotice;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;
  bool _emojiOpen = false;

  /// The system keyboard's height, remembered while it is up so the emoji
  /// panel can be exactly as tall when it replaces it. The fallback is only
  /// used before the keyboard has ever been seen.
  double _panelHeight = 280;

  /// Swaps the keyboard for the emoji panel, or back again.
  ///
  /// Both cannot be up at once: opening the panel dismisses the keyboard, and
  /// the keyboard button gives focus back, which brings it up and closes the
  /// panel with it.
  void _toggleEmoji() {
    if (_blocked) {
      _refuse();
      return;
    }
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _emojiOpen = true);
    }
  }

  /// Non-null only while a recording is running.
  VoiceRecorder? _recorder;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  /// Everything loaded from `shortcuts`, and the slash token being typed.
  List<QuickReply> _quickReplies = const <QuickReply>[];
  bool _quickRepliesLoading = false;
  bool _quickRepliesLoaded = false;
  String? _slashQuery;

  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _blocked => !widget.windowOpen;
  bool get _recording => _recorder != null;

  /// The panel is open whenever the field holds a bare `/token`.
  bool get _slashOpen => _slashQuery != null && !_recording;

  List<QuickReply> get _slashMatches =>
      filterQuickReplies(_quickReplies, _slashQuery ?? '');

  /// Watches the field for a slash token and loads the replies on first use.
  void _onTextChanged(String value) {
    final query = widget.loadQuickReplies == null
        ? null
        : quickReplyQuery(value);

    setState(() => _slashQuery = query);
    if (query != null) _ensureQuickReplies();
  }

  Future<void> _ensureQuickReplies() async {
    if (_quickRepliesLoaded || _quickRepliesLoading) return;
    final load = widget.loadQuickReplies;
    if (load == null) return;

    setState(() => _quickRepliesLoading = true);
    try {
      final replies = await load();
      if (mounted) setState(() => _quickReplies = replies);
    } finally {
      if (mounted) {
        setState(() {
          _quickRepliesLoading = false;
          _quickRepliesLoaded = true;
        });
      }
    }
  }

  /// Swaps the typed `/token` for the reply itself, ready to edit or send.
  void _useQuickReply(QuickReply reply) {
    _controller
      ..text = reply.message
      ..selection = TextSelection.collapsed(offset: reply.message.length);
    setState(() => _slashQuery = null);
    _focusNode.requestFocus();
  }

  /// Refuses the action and brings the explanation back.
  void _refuse() {
    if (_emojiOpen) setState(() => _emojiOpen = false);
    widget.onBlocked();
  }

  void _onAttachSelected(AttachOption option) {
    // Templates are the way out of a closed window, so they always work.
    if (option == AttachOption.template) {
      widget.onTemplates();
      return;
    }
    // Saving a quick reply sends nothing, so the window does not apply.
    if (option == AttachOption.quickReply) {
      _createQuickReply();
      return;
    }
    if (_blocked) {
      _refuse();
      return;
    }
    widget.onAttach(option);
  }

  /// Opens the New quick reply sheet and, once one is saved, puts it straight
  /// into the `/` menu without a refetch.
  Future<void> _createQuickReply() async {
    final create = widget.onCreateQuickReply;
    if (create == null) {
      widget.onAttach(AttachOption.quickReply);
      return;
    }

    final reply = await create();
    if (reply == null || !mounted) return;

    setState(() {
      // If the list was never fetched, the first `/` will fetch it — with
      // this reply already in it — so there is nothing to add yet.
      if (_quickRepliesLoaded) {
        _quickReplies = <QuickReply>[..._quickReplies, reply]
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      }
    });
  }

  Future<void> _openSchedule() async {
    final scheduled = await showScheduleMessageSheet(
      context,
      draft: _controller.text,
    );
    if (scheduled != null && mounted) widget.onSchedule(scheduled);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Not awaited: dispose() cannot be async, and the recorder is being
    // thrown away with the screen either way.
    unawaited(_recorder?.cancel());
    unawaited(_recorder?.dispose());
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Opens the microphone and swaps the bar for the recording strip.
  Future<void> _startRecording() async {
    if (_blocked) {
      _refuse();
      return;
    }
    if (_recording || _sending) return;

    final recorder = widget.recorderBuilder?.call() ?? DeviceVoiceRecorder();
    try {
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        widget.onRecorderProblem(kMicrophoneDeniedMessage);
        return;
      }
      await recorder.start();
    } on VoiceRecorderException catch (error) {
      await recorder.dispose();
      widget.onRecorderProblem(error.message);
      return;
    } catch (error) {
      await recorder.dispose();
      widget.onRecorderProblem('The microphone could not start: $error');
      return;
    }
    if (!mounted) {
      await recorder.cancel();
      await recorder.dispose();
      return;
    }

    // The keyboard and the emoji grid both fight the strip for the same space.
    _focusNode.unfocus();
    setState(() {
      _recorder = recorder;
      _elapsed = Duration.zero;
      _emojiOpen = false;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  /// Throws the recording away without sending anything.
  Future<void> _cancelRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    _ticker?.cancel();
    _ticker = null;
    setState(() => _recorder = null);

    await recorder.cancel();
    await recorder.dispose();
  }

  /// Stops the recording and hands the clip up to be uploaded and sent.
  Future<void> _finishRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _recorder = null;
      _sending = true;
    });

    try {
      final clip = await recorder.stop();
      if (clip == null) {
        widget.onRecorderProblem('That recording was empty — nothing to send.');
        return;
      }
      await widget.onVoiceNote(clip);
    } on VoiceRecorderException catch (error) {
      widget.onRecorderProblem(error.message);
    } finally {
      await recorder.dispose();
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (_blocked) {
      _refuse();
      return;
    }

    setState(() => _sending = true);
    try {
      if (await widget.onSend(text)) {
        _controller.clear();
        // A sent message can leave a stale slash query behind it.
        _slashQuery = null;
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focusNode.requestFocus();
      }
    }
  }

  void _insertEmoji(String emoji) {
    final (text, caret) =
        spliceEmoji(_controller.text, _controller.selection, emoji);
    _controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: caret);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // While the keyboard is up its height is the inset; remembering it lets
    // the emoji panel take exactly that space when the keyboard goes away.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 120) _panelHeight = inset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_blocked && !widget.noticeHidden)
          _WindowNotice(
            onTemplates: widget.onTemplates,
            onDismiss: widget.onDismissNotice,
          ),
        Material(
          // The surround stays as dark as the thread so the lighter pill reads
          // as a filled shape. On the near-identical grey it used to sit on,
          // the colour edge looked like an outline.
          color: Thread.background,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_slashOpen)
                  QuickRepliesPanel(
                    replies: _slashMatches,
                    loading: _quickRepliesLoading,
                    onPick: _useQuickReply,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: _inputBar(),
                ),
                // The emoji panel goes BELOW the bar and takes the keyboard's
                // place, at the keyboard's own height — WhatsApp swaps one for
                // the other. Above the bar it sat on top of the keyboard and
                // pushed the whole conversation off the screen.
                if (_emojiOpen)
                  SizedBox(
                    height: _panelHeight,
                    child: widget.emojiPickerBuilder?.call(_insertEmoji) ??
                        EmojiPicker(onPick: _insertEmoji, height: _panelHeight),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The rounded bar plus the circular send/mic button beside it, as in the
  /// mockup: `+`, emoji, field, attach, camera and schedule live in the pill;
  /// the microphone sits outside it.
  Widget _inputBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: _recording
              ? _RecordingStrip(
                  elapsed: _elapsed,
                  onCancel: _cancelRecording,
                )
              : _textPill(),
        ),
        const SizedBox(width: 8),
        _SendOrMicButton(
          hasText: _hasText,
          recording: _recording,
          sending: _sending,
          onPressed: _recording
              ? _finishRecording
              : (_hasText ? _send : _startRecording),
        ),
      ],
    );
  }

  Widget _textPill() {
    return Container(
            constraints: const BoxConstraints(minHeight: kComposerRowHeight),
            // A filled pill with no outline, as WhatsApp draws it.
            decoration: BoxDecoration(
              color: Thread.input,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                AttachButton(
                  onSelected: _onAttachSelected,
                  rowHeight: kComposerRowHeight,
                ),
                _BarIcon(
                  icon: _emojiOpen
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined,
                  tooltip: _emojiOpen ? 'Keyboard' : 'Emoji',
                  active: _emojiOpen,
                  onPressed: _toggleEmoji,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_sending,
                    // Kept visible but inert while the window is closed, so
                    // tapping explains itself rather than doing nothing.
                    readOnly: _blocked,
                    // Focusing the field raises the keyboard, so the panel
                    // has to give way or the two stack up.
                    onTap: _blocked
                        ? _refuse
                        : (_emojiOpen
                            ? () => setState(() => _emojiOpen = false)
                            : null),
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    onChanged: _onTextChanged,
                    // 15px at 1.4 is a 21px line; with 12.5px above and
                    // below that is the row height exactly, so a one-line
                    // field is as tall as the buttons beside it.
                    //
                    // The extra leading has to be split evenly. Flutter's
                    // default hands most of it to the ascent, which pushed
                    // the glyphs a few pixels below the icons' centre line.
                    style: const TextStyle(
                      color: Thread.text,
                      fontSize: 15,
                      height: 1.4,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: Wa.accent,
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      hintStyle: TextStyle(
                        color: Thread.meta,
                        fontSize: 15,
                        height: 1.4,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                      // The app theme fills and outlines every field by
                      // default; both are cleared here or the pill gets a
                      // second box drawn inside it. disabledBorder matters
                      // too — the field is disabled while a send is in
                      // flight, which would otherwise show the outline.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      // Still 25px in total, but weighted to the bottom:
                      // Inter's glyphs sit low in their line box, and even
                      // leading left the text a couple of pixels under the
                      // icons' centre line. Measured in a real browser, not
                      // the test font.
                      contentPadding: EdgeInsets.fromLTRB(0, 10.5, 0, 14.5),
                    ),
                  ),
                ),
                // Document and Camera live in the `+` menu only — repeating
                // them in the bar crowded it without adding anything.
                _BarIcon(
                  icon: Icons.schedule,
                  tooltip: 'Schedule message',
                  onPressed: _openSchedule,
                ),
              ],
            ),
    );
  }
}

/// What the text pill is replaced by while the microphone is open: a blinking
/// red dot, the elapsed time, and a bin to throw the take away.
class _RecordingStrip extends StatelessWidget {
  const _RecordingStrip({required this.elapsed, required this.onCancel});

  final Duration elapsed;
  final VoidCallback onCancel;

  String get _clock {
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: Thread.input,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.delete_outline, size: 22),
            color: Thread.warning,
            tooltip: 'Discard recording',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          ),
          const _BlinkingDot(),
          const SizedBox(width: 8),
          Text(
            _clock,
            style: const TextStyle(
              color: Thread.text,
              fontSize: 15,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Recording…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Thread.meta, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// The red dot beside the timer. It fades rather than hard-blinks so it does
/// not read as a broken frame.
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_controller),
      child: Container(
        height: 9,
        width: 9,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The circular button beside the bar. WhatsApp's own swap: a microphone
/// while the field is empty, the send arrow as soon as there is text — or
/// while a recording is running, since stopping it sends it.
class _SendOrMicButton extends StatelessWidget {
  const _SendOrMicButton({
    required this.hasText,
    required this.recording,
    required this.sending,
    required this.onPressed,
  });

  final bool hasText;
  final bool recording;
  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: 44,
      child: FilledButton(
        onPressed: sending ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Wa.accent,
          disabledBackgroundColor: Wa.accent.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(),
        ),
        child: sending
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                hasText || recording ? Icons.send_rounded : Icons.mic,
                size: 20,
              ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Every control in the bar is boxed to the single-line field's height
    // and centred in it. The row aligns to the bottom so the icons follow
    // the last line when the field grows — and with matching boxes, "bottom"
    // and "centred" are the same thing while there is one line. Before this
    // the + was 34px, the icons 38px and the field 46px, and each sat at a
    // different height.
    return SizedBox(
      height: kComposerRowHeight,
      child: Center(
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          color: active ? Wa.accent : Thread.meta,
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        ),
      ),
    );
  }
}

/// A single thin amber strip above the bar — it explains, it does not block.
class _WindowNotice extends StatelessWidget {
  const _WindowNotice({required this.onTemplates, required this.onDismiss});

  final VoidCallback onTemplates;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Thread.warningBackground,
      padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
      child: Row(
        children: <Widget>[
          Container(width: 3, height: 22, color: Thread.warning),
          const SizedBox(width: 8),
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Thread.warning),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              '24-hour window expired',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Thread.text, fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: onTemplates,
            style: TextButton.styleFrom(
              foregroundColor: Thread.warning,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Templates',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 14),
              color: Thread.meta,
              tooltip: 'Hide',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
        ],
      ),
    );
  }
}
