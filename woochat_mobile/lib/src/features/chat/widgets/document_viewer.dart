import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/message.dart';
import '../../../theme/wa_colors.dart';

/// A PDF opened from a chat, rendered inside the app — the way WhatsApp
/// opens one, rather than handing the link to a browser tab.
///
/// Pinch to zoom, scroll through the pages, ✕ to come back to the chat. An
/// "open elsewhere" action in the bar is the way out for anyone who wants
/// the file in another app; it is never the first thing that happens.
Future<void> showDocumentViewer(
  BuildContext context, {
  required MessageAttachment attachment,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => _DocumentViewer(attachment: attachment),
    ),
  );
}

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.attachment});

  final MessageAttachment attachment;

  Future<void> _openElsewhere(BuildContext context) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not open ${attachment.name}.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.url);
    return Scaffold(
      backgroundColor: Wa.background,
      appBar: AppBar(
        backgroundColor: Wa.header,
        foregroundColor: Wa.title,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          attachment.name.isEmpty ? 'Document' : attachment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in another app',
            onPressed: () => _openElsewhere(context),
          ),
        ],
      ),
      body: uri == null
          ? const _Problem(text: 'This file has no address to load from.')
          : PdfViewer.uri(
              uri,
              key: const ValueKey<String>('document-pdf'),
              params: PdfViewerParams(
                backgroundColor: Wa.background,
                loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                    const Center(
                  child: CircularProgressIndicator(color: Wa.accent),
                ),
                errorBannerBuilder: (context, error, stackTrace, ref) =>
                    _Problem(text: 'Could not open this file.\n$error'),
              ),
            ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Thread.meta, fontSize: 14),
        ),
      ),
    );
  }
}
