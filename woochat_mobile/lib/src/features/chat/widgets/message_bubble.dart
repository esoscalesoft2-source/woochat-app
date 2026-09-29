import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants.dart';
import '../../../core/formatting.dart';
import '../../../models/message.dart';
import '../../../theme/wa_colors.dart';
import 'voice_note_bubble.dart';

// Thread's colours live with the rest of the palette; re-exported so the
// many `import 'message_bubble.dart' show Thread` sites keep working.
export '../../../theme/wa_colors.dart' show Thread;

/// A single message bubble.
/// WhatsApp's bubble widths. A picture never grows past the first; text
/// gets a little more room. Both also stay under 75% of the screen, so a
/// phone is unaffected — these only bite on a tablet or a browser window.
const double kImageBubbleMaxWidth = 330;
const double kTextBubbleMaxWidth = 520;

/// A picture taller than this is cropped rather than scrolled past.
const double kImageBubbleMaxHeight = 420;

/// Where a file in a bubble stands on this device.
enum AttachmentSaveState { notSaved, saving, saved }

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.repliedTo,
    this.repliedToName,
    this.onOpenAttachment,
    this.onDownloadAttachment,
    this.saveState = AttachmentSaveState.notSaved,
    this.autoLoadMedia = true,
    this.onLongPress,
    this.onCancelScheduled,
    this.showTail = true,
    this.avatar,
  });

  /// Pulls a queued message before the server sends it. Only offered on a
  /// row whose status is still `scheduled`.
  final VoidCallback? onCancelScheduled;

  /// Holding the bubble — the message actions (forward, copy) hang off it.
  final VoidCallback? onLongPress;

  /// The contact's picture, shown on a voice note the way WhatsApp does.
  final Widget? avatar;

  /// Whether this bubble opens a run and so carries the little tail. The rest
  /// of a run sits tucked underneath without one, as WhatsApp draws it.
  final bool showTail;

  final Message message;

  /// The message this one quotes, when it is loaded.
  final Message? repliedTo;
  final String? repliedToName;
  final ValueChanged<MessageAttachment>? onOpenAttachment;

  /// The ⬇ on a file row. Saving is only ever this, never a side effect of
  /// tapping the file — tapping it opens it, or says it cannot be opened.
  final ValueChanged<MessageAttachment>? onDownloadAttachment;

  /// Whether the file is already on this device. Once it is, the ⬇ goes —
  /// WhatsApp's row after a download — and while it is being fetched a
  /// spinner stands in for it.
  final AttachmentSaveState saveState;

  /// Whether a picture loads by itself. False under a "No media" or
  /// mobile-data rule from Storage and data: the bubble then shows a
  /// tap-to-load tile in the picture's place until it is asked for.
  final bool autoLoadMedia;

  @override
  Widget build(BuildContext context) {
    final isOutbound = message.isOutbound;
    final attachment = message.attachment;
    final body = message.body;

    // A picture on its own fills the bubble edge to edge, with the time laid
    // over it — WhatsApp only draws a frame around a photo when there is
    // something else in the bubble with it: a caption, a quote, a failure.
    final bareImage =
        attachment != null &&
        attachment.isImage &&
        body.isEmpty &&
        repliedTo == null &&
        message.reaction == null &&
        !message.hasFailed;

    return Align(
      alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          // WhatsApp's own metrics: 8px from the screen edge, a hair's gap
          // inside a run and a wider one before a new run, never past 75%.
          margin: EdgeInsets.only(
            left: 8,
            right: 8,
            top: showTail ? 6 : 1.5,
            bottom: 1.5,
          ),
          // Never past 75% of the screen, and never past an absolute width
          // either: on a desktop browser 75% is 1400px, which turned a
          // screenshot into a banner and a sentence into a line across the
          // room. WhatsApp caps a picture at ~330px and text a little wider.
          constraints: BoxConstraints(
            maxWidth: math.min(
              MediaQuery.sizeOf(context).width * 0.75,
              attachment != null && (attachment.isImage || attachment.isVideo)
                  ? kImageBubbleMaxWidth
                  : kTextBubbleMaxWidth,
            ),
          ),
          child: CustomPaint(
            // The bubble is painted rather than decorated so the tail is part
            // of its shape instead of something stuck on beside it.
            painter: _BubblePainter(
              color: isOutbound ? Thread.outbound : Thread.inbound,
              outbound: isOutbound,
              tail: showTail,
            ),
            child: Padding(
              // A bare picture gets no frame at all — only the strip the tail
              // needs, so the image never paints over it.
              padding: bareImage
                  ? EdgeInsets.only(
                      left: isOutbound ? 0 : _BubblePainter.tailWidth,
                      right: isOutbound ? _BubblePainter.tailWidth : 0,
                    )
                  : attachment == null
                  ? EdgeInsets.fromLTRB(
                      isOutbound ? 9 : 9 + _BubblePainter.tailWidth,
                      6,
                      isOutbound ? 9 + _BubblePainter.tailWidth : 9,
                      7,
                    )
                  : EdgeInsets.fromLTRB(
                      isOutbound ? 3 : 3 + _BubblePainter.tailWidth,
                      3,
                      isOutbound ? 3 + _BubblePainter.tailWidth : 3,
                      3,
                    ),
              child: bareImage
                  ? ClipRRect(
                      // Matches the painted body exactly, so the picture takes
                      // the bubble's own shape.
                      borderRadius: _BubblePainter.corners(
                        outbound: isOutbound,
                        tail: showTail,
                      ),
                      child: Stack(
                        children: <Widget>[
                          _AttachmentView(
                            attachment: attachment,
                            onOpen: onOpenAttachment,
                            onDownload: onDownloadAttachment,
                            saveState: saveState,
                            autoLoad: autoLoadMedia,
                            outbound: isOutbound,
                            avatar: avatar,
                            rounded: false,
                          ),
                          Positioned(
                            right: 6,
                            bottom: 5,
                            child: _StampChip(
                              stamp: TimeFormat.bubbleStamp(message.createdAt),
                              status: isOutbound ? message.status : null,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      // With no text, the stamp is the only thing under the
                      // media and it should hug the right edge of THAT — an
                      // Align would grow to the bubble's maximum width and
                      // drag a voice note out to 75% of the screen.
                      crossAxisAlignment: body.isEmpty && attachment != null
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (repliedTo != null)
                          _QuotedMessage(
                            message: repliedTo!,
                            name: repliedToName ?? 'Message',
                          ),
                        // `messages.template_name` is deliberately not drawn: WhatsApp
                        // shows a template message as an ordinary bubble, and the label
                        // read as part of the message text.
                        if (attachment != null)
                          _AttachmentView(
                            attachment: attachment,
                            onOpen: onOpenAttachment,
                            onDownload: onDownloadAttachment,
                            saveState: saveState,
                            autoLoad: autoLoadMedia,
                            outbound: isOutbound,
                            avatar: avatar,
                          ),
                        Padding(
                          padding: attachment == null
                              ? EdgeInsets.zero
                              : const EdgeInsets.fromLTRB(6, 6, 4, 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (message.reaction != null) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  message.reaction!,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                              _BodyWithStamp(
                                body: body,
                                // A queued row is stamped with WHEN IT WILL
                                // GO, not when it was written; the clock in
                                // place of ticks says the same.
                                stamp: message.isScheduled
                                    ? scheduledStamp(message.scheduledAt)
                                    : TimeFormat.bubbleStamp(message.createdAt),
                                status: isOutbound ? message.status : null,
                                outbound: isOutbound,
                              ),
                              if (message.hasFailed &&
                                  message.sendErrorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    message.sendErrorMessage!,
                                    style: const TextStyle(
                                      color: Wa.error,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (isOutbound && message.isScheduled)
                                _ScheduledFooter(
                                  message: message,
                                  onCancel: onCancelScheduled,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bubble's shape: a rounded rectangle with WhatsApp's little tail at the
/// top corner nearest the sender.
///
/// The tail's width is reserved on that side for every bubble, tailed or not,
/// so the bodies of a run all line up and only the first one sprouts a tail.
class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.color,
    required this.outbound,
    required this.tail,
  });

  final Color color;
  final bool outbound;
  final bool tail;

  static const double tailWidth = 7;
  static const double _radius = 16;

  /// The body's corners. Shared so a picture filling the bubble can be
  /// clipped to exactly the shape that gets painted behind it.
  static BorderRadius corners({required bool outbound, required bool tail}) {
    return BorderRadius.only(
      topLeft: Radius.circular(!outbound && tail ? 0 : _radius),
      topRight: Radius.circular(outbound && tail ? 0 : _radius),
      bottomLeft: const Radius.circular(_radius),
      bottomRight: const Radius.circular(_radius),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    // The body stops short of the edge on the sender's side; that strip is
    // where the tail lives.
    final left = outbound ? 0.0 : tailWidth;
    final right = outbound ? size.width - tailWidth : size.width;

    // The tailed corner is square so the tail merges into it.
    final shape = corners(outbound: outbound, tail: tail);
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        left,
        0,
        right,
        size.height,
        topLeft: shape.topLeft,
        topRight: shape.topRight,
        bottomLeft: shape.bottomLeft,
        bottomRight: shape.bottomRight,
      ),
      paint,
    );

    if (!tail) return;

    // A small flag off the top corner, curving back into the body.
    final path = Path();
    if (outbound) {
      path
        ..moveTo(right, 0)
        ..lineTo(size.width, 0)
        ..cubicTo(size.width - 1, 5, right + 2.5, 9.5, right, 12)
        ..close();
    } else {
      path
        ..moveTo(left, 0)
        ..lineTo(0, 0)
        ..cubicTo(1, 5, left - 2.5, 9.5, left, 12)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.color != color || old.outbound != outbound || old.tail != tail;
}

/// The quoted block above a reply, driven by `reply_to_message_id`.
class _QuotedMessage extends StatelessWidget {
  const _QuotedMessage({required this.message, required this.name});

  final Message message;
  final String name;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final preview = message.body.isNotEmpty
        ? message.body
        : (attachment != null ? attachment.name : 'Message');

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0x33000000),
        border: Border(left: BorderSide(color: Wa.accent, width: 4)),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Wa.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Thread.meta, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Renders real media stored on the message.
/// The time (and ticks) laid over a picture, on the dark pill WhatsApp uses
/// so it stays readable whatever the photo is.
class _StampChip extends StatelessWidget {
  const _StampChip({required this.stamp, required this.status});

  final String stamp;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            stamp,
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 11,
              height: 1.2,
            ),
          ),
          if (status != null) ...<Widget>[
            const SizedBox(width: 3),
            _DeliveryIcon(status: status),
          ],
        ],
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({
    required this.attachment,
    required this.onOpen,
    required this.onDownload,
    required this.saveState,
    required this.autoLoad,
    required this.outbound,
    this.avatar,
    this.rounded = true,
  });

  final bool outbound;

  /// The sender's picture, for the little avatar on a voice note.
  final Widget? avatar;

  final MessageAttachment attachment;
  final ValueChanged<MessageAttachment>? onOpen;
  final ValueChanged<MessageAttachment>? onDownload;
  final AttachmentSaveState saveState;
  final bool autoLoad;

  /// False when the bubble already clips the picture to its own shape, so
  /// rounding here would cut a second, smaller corner inside it.
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    // A voice note gets WhatsApp's player rather than a file row.
    if (attachment.isAudio) {
      return VoiceNoteBubble(
        url: attachment.url,
        outbound: outbound,
        avatar: avatar,
      );
    }
    if (attachment.isImage) {
      return _LazyImage(
        attachment: attachment,
        autoLoad: autoLoad,
        rounded: rounded,
        onOpen: onOpen,
        onDownload: onDownload,
        saveState: saveState,
      );
    }
    return _FileTile(
      attachment: attachment,
      onOpen: onOpen,
      onDownload: onDownload,
      saveState: saveState,
    );
  }
}

/// A picture that loads by itself, or waits to be asked — the auto-download
/// rule from Storage and data decides which. Asking is a tap on the tile,
/// and the answer is remembered for as long as the bubble lives.
class _LazyImage extends StatefulWidget {
  const _LazyImage({
    required this.attachment,
    required this.autoLoad,
    required this.rounded,
    required this.onOpen,
    required this.onDownload,
    required this.saveState,
  });

  final MessageAttachment attachment;
  final bool autoLoad;
  final bool rounded;
  final ValueChanged<MessageAttachment>? onOpen;
  final ValueChanged<MessageAttachment>? onDownload;
  final AttachmentSaveState saveState;

  @override
  State<_LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<_LazyImage> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    if (!widget.autoLoad && !_asked) {
      return InkWell(
        key: const ValueKey<String>('media-tap-to-load'),
        onTap: () => setState(() => _asked = true),
        borderRadius: BorderRadius.circular(widget.rounded ? 8 : 0),
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(widget.rounded ? 8 : 0),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.download_outlined, size: 28, color: Thread.meta),
              SizedBox(height: 6),
              Text(
                'Tap to load photo',
                style: TextStyle(color: Thread.meta, fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }
    final onOpen = widget.onOpen;
    final rounded = widget.rounded;
    final onDownload = widget.onDownload;
    final saveState = widget.saveState;
    // The picture keeps its own shape: full bubble width, height from its
    // aspect ratio, cropped only once it would be taller than a phone
    // screen's worth. Fixing the height to 200 is what sliced tall
    // screenshots into strips.
    return GestureDetector(
      onTap: onOpen == null ? null : () => onOpen(attachment),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rounded ? 8 : 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 120,
            maxHeight: kImageBubbleMaxHeight,
          ),
          child: Image.network(
            attachment.url,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Wa.accent,
                      ),
                    ),
                  ),
            errorBuilder: (_, _, _) => _FileTile(
              attachment: attachment,
              onOpen: onOpen,
              onDownload: onDownload,
              saveState: saveState,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.attachment,
    required this.onOpen,
    required this.onDownload,
    required this.saveState,
  });

  final MessageAttachment attachment;
  final ValueChanged<MessageAttachment>? onOpen;
  final ValueChanged<MessageAttachment>? onDownload;
  final AttachmentSaveState saveState;

  @override
  Widget build(BuildContext context) {
    final icon = switch (attachment.type) {
      'video' => Icons.play_circle_outline,
      'audio' || 'voice' => Icons.graphic_eq,
      'document' => Icons.description_outlined,
      _ => Icons.attach_file,
    };

    return InkWell(
      onTap: onOpen == null ? null : () => onOpen!(attachment),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: Thread.meta),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Thread.text, fontSize: 13),
              ),
            ),
            // WhatsApp's ⬇ on a file: saving is a thing you ask for, not
            // what happens when you tap the name to look at it. Once the
            // file is here the icon goes, so the row says "yours already".
            if (onDownload != null &&
                saveState == AttachmentSaveState.notSaved) ...<Widget>[
              const SizedBox(width: 6),
              IconButton(
                key: const ValueKey<String>('attachment-download'),
                onPressed: () => onDownload!(attachment),
                icon: const Icon(Icons.download_outlined, size: 20),
                color: Thread.meta,
                tooltip: 'Download',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ] else if (saveState == AttachmentSaveState.saving) ...<Widget>[
              const SizedBox(width: 6),
              const SizedBox(
                key: ValueKey<String>('attachment-saving'),
                width: 30,
                height: 30,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Thread.meta,
                    ),
                  ),
                ),
              ),
            ] else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// The message text with the timestamp tucked into its last line.
///
/// WhatsApp does not put the time on a row of its own — it reserves just
/// enough room at the end of the text and drops the stamp into it, so a short
/// message stays one line. The reservation is a zero-height [WidgetSpan],
/// which makes the wrap exact rather than a guess at how many spaces to add.
class _BodyWithStamp extends StatelessWidget {
  const _BodyWithStamp({
    required this.body,
    required this.stamp,
    required this.status,
    required this.outbound,
  });

  final String body;
  final String stamp;

  /// Null for inbound messages, which carry no ticks.
  final String? status;
  final bool outbound;

  static const double _stampSize = 11;
  static const double _tickGap = 3;
  static const double _tickWidth = 14;

  /// Breathing room between the last word and the stamp. 8px read as the
  /// date running into the text once the stamp grew a day ("17 Sep, 6:30 PM")
  /// on a queued message; WhatsApp leaves about this much.
  static const double _lead = 16;

  /// How wide the stamp row will actually be, in the font it will actually
  /// use. A guessed constant (62px) was narrower than "10:24 AM ✓✓" in Inter,
  /// so the time was drawn straight over the end of the text.
  double _reservedFor(BuildContext context, TextStyle stampStyle) {
    final painter = TextPainter(
      text: TextSpan(text: stamp, style: stampStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final ticks = status == null ? 0 : _tickGap + _tickWidth;
    return _lead + painter.width + ticks;
  }

  @override
  Widget build(BuildContext context) {
    // Outbound stamps sit on the green fill, where plain grey goes muddy.
    // WhatsApp uses the same 60% white on both bubble colours.
    final metaColor = Thread.meta;

    // Merged with the ambient style so the measurement uses the same font
    // family the Text below will be drawn in.
    final stampStyle = DefaultTextStyle.of(context).style
        .merge(TextStyle(color: metaColor, fontSize: _stampSize, height: 1));

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(stamp, style: stampStyle),
        if (status != null) ...<Widget>[
          const SizedBox(width: _tickGap),
          _DeliveryIcon(status: status),
        ],
      ],
    );

    // With no text to sit beside — an image, a file, a voice note — the stamp
    // still belongs on the right. Returning the row bare left it hard against
    // the left edge of the bubble.
    // With no text to sit beside — an image, a file, a voice note — the
    // enclosing column right-aligns it; see the bubble's crossAxisAlignment.
    if (body.isEmpty) return meta;

    return Stack(
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: body),
              WidgetSpan(
                child: SizedBox(
                  width: _reservedFor(context, stampStyle),
                  height: 1,
                ),
              ),
            ],
          ),
          // WhatsApp Android renders message text at 16sp.
          style: const TextStyle(color: Thread.text, fontSize: 16, height: 1.3),
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      MessageStatus.read => (Icons.done_all, Wa.tickBlue),
      MessageStatus.delivered => (Icons.done_all, Thread.meta),
      MessageStatus.sent => (Icons.done, Thread.meta),
      MessageStatus.failed => (Icons.error_outline, Wa.error),
      MessageStatus.scheduled => (Icons.schedule, Wa.warning),
      _ => (Icons.schedule, Thread.meta),
    };
    return Icon(icon, size: 14, color: color);
  }
}

/// `scheduled_at` as the bubble shows it: "16 Sep, 9:30 AM" — the day is
/// always spelt, since a queued message usually goes on a later one.
String scheduledStamp(DateTime? at) =>
    at == null ? '' : DateFormat('d MMM, h:mm a').format(at.toLocal());

/// What sits under a queued bubble: why it is waiting, if it is being held,
/// and the way to pull it back.
class _ScheduledFooter extends StatelessWidget {
  const _ScheduledFooter({required this.message, required this.onCancel});

  final Message message;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final held = message.isHeldByMarketingCap;
    final retry = message.retryNote;
    final String? note = held
        ? "Held back by WhatsApp (customer's marketing limit) · retries "
              'automatically at ${scheduledStamp(message.scheduledAt)}'
        : retry;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Wa.warning,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      note,
                      key: const ValueKey<String>('scheduled-note'),
                      style: const TextStyle(color: Wa.warning, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          if (onCancel != null)
            InkWell(
              key: const ValueKey<String>('cancel-scheduled'),
              onTap: onCancel,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.close, size: 12, color: Thread.meta),
                    const SizedBox(width: 4),
                    Text(
                      held ? 'Cancel auto resend' : 'Cancel scheduled',
                      style: const TextStyle(
                        color: Thread.meta,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "TODAY" / date separator between message groups.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Thread.divider,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Wa.border),
        ),
        child: Text(
          TimeFormat.dayHeader(day).toUpperCase(),
          style: const TextStyle(
            color: Thread.meta,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// The WhatsApp doodle wallpaper behind the conversation.
///
/// Scaled to the full width and tiled downwards, matching the web app's
/// `background-size: 100% auto; background-repeat: repeat-y`.
class ThreadBackground extends StatelessWidget {
  const ThreadBackground({super.key, required this.child});

  static const String asset = 'assets/images/whatsapp_bg.png';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Thread.background,
        image: DecorationImage(
          image: AssetImage(asset),
          repeat: ImageRepeat.repeatY,
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
        ),
      ),
      child: child,
    );
  }
}
