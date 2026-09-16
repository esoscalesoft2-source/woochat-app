import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/wa_colors.dart';

/// WhatsApp's full-screen photo view: the picture on black, pinch and
/// double-tap to zoom, a caption along the bottom, ✕ to close. Stays inside
/// the app — a photo tapped in a chat should never bounce out to a browser.
Future<void> showImageViewer(
  BuildContext context, {
  required MessageAttachment attachment,
  String caption = '',
  String? title,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: _ImageViewer(
          attachment: attachment,
          caption: caption,
          title: title,
        ),
      ),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.attachment,
    required this.caption,
    required this.title,
  });

  final MessageAttachment attachment;
  final String caption;
  final String? title;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _zoom = TransformationController();

  /// Chrome (title, ✕, caption) hides on a tap so the picture has the whole
  /// screen, and comes back on the next tap — WhatsApp's behaviour.
  bool _chrome = true;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails details) {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    // Zoom in around the point that was tapped.
    final point = details.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-point.dx * 1.5, -point.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            onTap: () => setState(() => _chrome = !_chrome),
            onDoubleTapDown: _toggleZoom,
            onDoubleTap: () {},
            child: InteractiveViewer(
              key: const ValueKey<String>('image-viewer'),
              transformationController: _zoom,
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  widget.attachment.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                color: Wa.accent,
                              ),
                            ),
                  errorBuilder: (_, _, _) => const Center(
                    child: Text(
                      'This picture could not be loaded.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_chrome) ...<Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 56,
                  color: Colors.black54,
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.title ?? widget.attachment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.caption.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Text(
                      widget.caption.trim(),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
