import 'package:flutter/material.dart';

import '../../../data/attachment_picker.dart';
import '../../../theme/wa_colors.dart';

/// What the preview hands back: the files still in the set (any can be
/// taken out before sending) and the caption.
class AttachmentSendChoice {
  const AttachmentSendChoice({required this.attachments, required this.caption});

  final List<PickedAttachment> attachments;

  /// Goes on the first file, the way the web app sends a multi-file attach.
  final String caption;
}

/// Confirms a picked file before it is uploaded, with an optional caption —
/// the step WhatsApp itself puts between choosing a file and sending it.
///
/// Returns the caption on Send (empty string when none was typed), or null
/// when the user backs out.
Future<String?> showAttachmentPreviewSheet(
  BuildContext context, {
  required PickedAttachment attachment,
  required String chatName,
}) async {
  final choice = await showAttachmentsPreviewSheet(
    context,
    attachments: <PickedAttachment>[attachment],
    chatName: chatName,
  );
  return choice?.caption;
}

/// The same preview for several files at once: a strip of thumbnails, each
/// removable, and one caption that goes on the first. Returns null when the
/// user backs out or removes every file.
///
/// [onAddMore] backs the + in the header: it opens the picker again and
/// returns what was picked, which joins the set (up to
/// [AttachmentPicker.maxMediaPerSend] in total).
Future<AttachmentSendChoice?> showAttachmentsPreviewSheet(
  BuildContext context, {
  required List<PickedAttachment> attachments,
  required String chatName,
  Future<List<PickedAttachment>> Function(int remaining)? onAddMore,
}) {
  return showModalBottomSheet<AttachmentSendChoice>(
    context: context,
    backgroundColor: Thread.composer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _AttachmentPreviewSheet(
      attachments: attachments,
      chatName: chatName,
      onAddMore: onAddMore,
    ),
  );
}

class _AttachmentPreviewSheet extends StatefulWidget {
  const _AttachmentPreviewSheet({
    required this.attachments,
    required this.chatName,
    required this.onAddMore,
  });

  final List<PickedAttachment> attachments;
  final String chatName;
  final Future<List<PickedAttachment>> Function(int remaining)? onAddMore;

  @override
  State<_AttachmentPreviewSheet> createState() =>
      _AttachmentPreviewSheetState();
}

class _AttachmentPreviewSheetState extends State<_AttachmentPreviewSheet> {
  final _caption = TextEditingController();
  late final List<PickedAttachment> _files = <PickedAttachment>[
    ...widget.attachments,
  ];

  /// The one shown large; the strip below picks it.
  int _current = 0;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  PickedAttachment get _shown => _files[_current];

  bool _adding = false;
  String? _error;

  int get _remaining => AttachmentPicker.maxMediaPerSend - _files.length;

  Future<void> _addMore() async {
    final add = widget.onAddMore;
    if (add == null || _adding) return;
    if (_remaining <= 0) {
      setState(() => _error =
          'You can send up to ${AttachmentPicker.maxMediaPerSend} at once.');
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final more = await add(_remaining);
      if (!mounted || more.isEmpty) return;
      setState(() {
        _files.addAll(more.take(_remaining));
        // Show the first of what just came in.
        _current = _files.length - more.take(_remaining).length;
      });
    } on AttachmentPickerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// WhatsApp puts a caption on images and videos only; on a document it
  /// shows beside the file, and audio carries none at all.
  bool get _captionable => _files.first.type != 'audio';

  void _remove(int index) {
    setState(() {
      _files.removeAt(index);
      if (_current >= _files.length) _current = _files.length - 1;
    });
    if (_files.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = _shown;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _files.length == 1
                            ? 'Send to ${widget.chatName}'
                            : 'Send ${_files.length} to ${widget.chatName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Thread.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.onAddMore != null)
                      _adding
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Wa.accent,
                                ),
                              ),
                            )
                          : IconButton(
                              key: const ValueKey<String>('attachment-add'),
                              onPressed: _addMore,
                              tooltip: 'Add more',
                              icon: const Icon(Icons.add, color: Wa.accent),
                            ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Wa.error, fontSize: 12.5),
                  ),
                ),
              const Divider(height: 1, color: Wa.divider),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _Preview(attachment: attachment),
                ),
              ),
              if (_files.length > 1)
                _Strip(
                  files: _files,
                  current: _current,
                  onPick: (index) => setState(() => _current = index),
                  onRemove: _remove,
                ),
              if (_captionable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TextField(
                    key: const ValueKey<String>('attachment-caption'),
                    controller: _caption,
                    style: const TextStyle(color: Thread.text),
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add a caption (optional)',
                      hintStyle: const TextStyle(color: Thread.meta),
                      filled: true,
                      fillColor: Thread.input,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    AttachmentSendChoice(
                      attachments: List<PickedAttachment>.unmodifiable(_files),
                      caption: _caption.text.trim(),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Wa.onAccent,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.send),
                  label: Text(_files.length == 1 ? 'Send' : 'Send ${_files.length}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The thumbnails under the big preview when several files are staged.
/// Tapping one shows it large; the ✕ on each takes it out of the set.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.files,
    required this.current,
    required this.onPick,
    required this.onRemove,
  });

  final List<PickedAttachment> files;
  final int current;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        key: const ValueKey<String>('attachment-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = files[index];
          final selected = index == current;
          return GestureDetector(
            onTap: () => onPick(index),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.only(top: 6, right: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? Wa.accent : Wa.divider,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: file.type == 'image'
                      ? Image.memory(
                          file.bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Thread.input,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Wa.accent,
                            ),
                          ),
                        )
                      : Container(
                          color: Thread.input,
                          child: Icon(
                            file.type == 'video'
                                ? Icons.videocam
                                : Icons.insert_drive_file,
                            color: Wa.accent,
                          ),
                        ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => onRemove(index),
                    child: Container(
                      key: ValueKey<String>('attachment-remove-$index'),
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.attachment});

  final PickedAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.type == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              attachment.bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _FileRow(attachment: attachment),
            ),
          ),
          const SizedBox(height: 8),
          _SizeLine(attachment: attachment),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FileRow(attachment: attachment),
        const SizedBox(height: 8),
        _SizeLine(attachment: attachment),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment});

  final PickedAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (attachment.type) {
      'video' => (Icons.videocam, const Color(0xFF2196F3)),
      'audio' => (Icons.music_note, const Color(0xFFEF4444)),
      'image' => (Icons.image, const Color(0xFF2196F3)),
      _ => (Icons.insert_drive_file, const Color(0xFF7B61FF)),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Thread.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              attachment.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Thread.text, fontSize: 14.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The file size, and a warning when it is over what WhatsApp will take.
class _SizeLine extends StatelessWidget {
  const _SizeLine({required this.attachment});

  final PickedAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final mb = attachment.bytes.length / (1024 * 1024);
    final size = mb >= 1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(attachment.bytes.length / 1024).round()} KB';

    final String? problem;
    if (attachment.isTooLarge) {
      problem = 'WhatsApp only accepts ${attachment.type} files up to '
          '${attachment.limitLabel}, so this will be refused.';
    } else if (!attachment.isSupportedFormat) {
      final allowed = PickedAttachment.supportedMimeTypes[attachment.type]!
          .map((mime) => mime.split('/').last)
          .toSet()
          .join(', ');
      problem = 'WhatsApp does not accept ${attachment.mimeType} — only '
          '$allowed. This will be refused.';
    } else {
      problem = null;
    }

    if (problem == null) {
      return Text(
        size,
        style: const TextStyle(color: Thread.meta, fontSize: 12),
      );
    }

    return Text(
      '$size — $problem',
      style: const TextStyle(color: Wa.warning, fontSize: 12),
    );
  }
}
