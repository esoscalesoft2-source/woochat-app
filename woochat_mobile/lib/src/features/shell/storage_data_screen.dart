import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../data/approved_templates_cache.dart';
import '../../data/downloads_repository.dart';
import '../../data/storage_settings.dart';
import '../../theme/wa_colors.dart';
import '../chat/widgets/confirm_dialog.dart';

/// Settings → Storage and data: the same page WhatsApp has, with the parts
/// of it this app actually does.
///
///  - Manage storage: the files saved from chats, and the template copy.
///  - Media upload quality: whether photos are shrunk before they go up.
///  - Media auto-download: which media loads by itself on mobile data,
///    and which on Wi-Fi.
Future<void> showStorageAndDataScreen(
  BuildContext context, {
  StorageSettings? settings,
  DownloadsRepository? downloads,
  Future<void> Function()? onReloadTemplates,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => StorageAndDataScreen(
        settings: settings ?? StorageSettings.instance,
        downloads: downloads ?? DownloadsRepository(),
        onReloadTemplates: onReloadTemplates ?? _reloadTemplates,
      ),
    ),
  );
}

Future<void> _reloadTemplates() async {
  await ApprovedTemplatesCache.instance.clear();
  await ApprovedTemplatesCache.instance.get();
}

class StorageAndDataScreen extends StatefulWidget {
  const StorageAndDataScreen({
    super.key,
    required this.settings,
    required this.downloads,
    required this.onReloadTemplates,
  });

  final StorageSettings settings;
  final DownloadsRepository downloads;
  final Future<void> Function() onReloadTemplates;

  @override
  State<StorageAndDataScreen> createState() => _StorageAndDataScreenState();
}

class _StorageAndDataScreenState extends State<StorageAndDataScreen> {
  late Future<int> _bytes = widget.downloads.totalBytes();

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_redraw);
    widget.settings.load();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Scaffold(
      backgroundColor: Wa.background,
      appBar: AppBar(
        backgroundColor: Wa.background,
        foregroundColor: Wa.title,
        elevation: 0,
        title: const Text('Storage and data'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: <Widget>[
          FutureBuilder<int>(
            future: _bytes,
            builder: (context, snapshot) => _Row(
              key: const ValueKey<String>('storage-manage'),
              icon: Icons.folder_outlined,
              title: 'Manage storage',
              subtitle: formatBytes(snapshot.data ?? 0),
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => _ManageStorageScreen(
                      downloads: widget.downloads,
                      onReloadTemplates: widget.onReloadTemplates,
                    ),
                  ),
                );
                if (mounted) {
                  setState(() => _bytes = widget.downloads.totalBytes());
                }
              },
            ),
          ),
          const Divider(height: 1, color: Wa.divider),

          _Row(
            key: const ValueKey<String>('storage-upload-quality'),
            icon: Icons.hd_outlined,
            title: 'Media upload quality',
            subtitle: settings.uploadQuality.label,
            onTap: () async {
              final picked = await _choose<UploadQuality>(
                context,
                title: 'Media upload quality',
                options: UploadQuality.values,
                selected: settings.uploadQuality,
                labelOf: (q) => q.label,
                hintOf: (q) => q == UploadQuality.standard
                    ? 'Photos are resized before sending — faster, and '
                        'what WhatsApp itself does.'
                    : 'Photos are sent as picked. Larger and slower.',
              );
              if (picked != null) await settings.setUploadQuality(picked);
            },
          ),
          const Divider(height: 1, color: Wa.divider),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Media auto-download',
              style: TextStyle(color: Wa.title, fontSize: 14),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Voice messages are always automatically downloaded. Photos '
              'not chosen show as "Tap to load"; files not chosen keep '
              'their ⬇ until you tap it.',
              style: TextStyle(color: Wa.secondaryText, fontSize: 12.5),
            ),
          ),
          _Row(
            key: const ValueKey<String>('storage-auto-mobile'),
            title: 'When using mobile data',
            subtitle: settings.onMobileData.label,
            onTap: () async {
              final picked = await _chooseAutoDownload(
                context,
                title: 'When using mobile data',
                selected: settings.onMobileData,
              );
              if (picked != null) await settings.setOnMobileData(picked);
            },
          ),
          _Row(
            key: const ValueKey<String>('storage-auto-wifi'),
            title: 'When connected on Wi-Fi',
            subtitle: settings.onWifi.label,
            onTap: () async {
              final picked = await _chooseAutoDownload(
                context,
                title: 'When connected on Wi-Fi',
                selected: settings.onWifi,
              );
              if (picked != null) await settings.setOnWifi(picked);
            },
          ),
        ],
      ),
    );
  }

  /// WhatsApp's dialog: a tick for each of Photos, Audio, Videos,
  /// Documents, and OK. Returns the new set, or null on Cancel.
  Future<AutoDownload?> _chooseAutoDownload(
    BuildContext context, {
    required String title,
    required AutoDownload selected,
  }) {
    var picked = selected;
    return showDialog<AutoDownload>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Wa.menu,
          title: Text(
            title,
            style: const TextStyle(color: Wa.title, fontSize: 17),
          ),
          contentPadding: const EdgeInsets.only(top: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final kind in MediaKind.values)
                CheckboxListTile(
                  key: ValueKey<String>('kind-${kind.name}'),
                  value: picked.has(kind),
                  activeColor: Wa.accent,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    kind.label,
                    style: const TextStyle(color: Wa.title, fontSize: 15),
                  ),
                  onChanged: (_) => setState(() => picked = picked.toggled(kind)),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Wa.secondaryText),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey<String>('kinds-ok'),
              onPressed: () => Navigator.of(context).pop(picked),
              style: TextButton.styleFrom(foregroundColor: Wa.accent),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1.6 GB", "12.4 MB", "820 KB" — one decimal above KB, none below.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

/// A radio-list dialog, the way WhatsApp picks one of a few.
Future<T?> _choose<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T) labelOf,
  String Function(T)? hintOf,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      backgroundColor: Wa.menu,
      title: Text(title, style: const TextStyle(color: Wa.title, fontSize: 17)),
      children: <Widget>[
        RadioGroup<T>(
          groupValue: selected,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final option in options)
                RadioListTile<T>(
                  key: ValueKey<String>('choice-${labelOf(option)}'),
                  value: option,
                  activeColor: Wa.accent,
                  title: Text(
                    labelOf(option),
                    style: const TextStyle(color: Wa.title, fontSize: 15),
                  ),
                  subtitle: hintOf == null
                      ? null
                      : Text(
                          hintOf(option),
                          style: const TextStyle(
                            color: Wa.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Manage storage: what is on this device from chats, and a way to clear
/// it. On the web the browser keeps the downloads, so only the template
/// copy is here.
class _ManageStorageScreen extends StatefulWidget {
  const _ManageStorageScreen({
    required this.downloads,
    required this.onReloadTemplates,
  });

  final DownloadsRepository downloads;
  final Future<void> Function() onReloadTemplates;

  @override
  State<_ManageStorageScreen> createState() => _ManageStorageScreenState();
}

class _ManageStorageScreenState extends State<_ManageStorageScreen> {
  late Future<int> _bytes = widget.downloads.totalBytes();
  bool _busy = false;

  Future<void> _clear() async {
    final sure = await showConfirmDialog(
      context,
      title: 'Clear downloaded files?',
      message: 'Files saved from chats will be removed from this device. '
          'They stay in the chats and can be downloaded again.',
      confirmLabel: 'Clear',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.downloads.clearAll();
      if (mounted) {
        setState(() => _bytes = widget.downloads.totalBytes());
        _say('Downloaded files cleared.');
      }
    } catch (error) {
      if (mounted) _say('Could not clear: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadTemplates() async {
    setState(() => _busy = true);
    try {
      await widget.onReloadTemplates();
      if (mounted) _say('Templates reloaded from the server.');
    } catch (error) {
      if (mounted) _say('Could not reload templates: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.background,
      appBar: AppBar(
        backgroundColor: Wa.background,
        foregroundColor: Wa.title,
        elevation: 0,
        title: const Text('Manage storage'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: <Widget>[
          FutureBuilder<int>(
            future: _bytes,
            builder: (context, snapshot) {
              final bytes = snapshot.data ?? 0;
              return _Row(
                key: const ValueKey<String>('storage-clear-downloads'),
                icon: Icons.download_outlined,
                title: 'Downloaded files',
                subtitle: bytes == 0
                    ? 'Nothing saved from chats yet'
                    : '${formatBytes(bytes)} · tap to clear'
                        // A browser's kept copies are separate from what
                        // its Save dialog wrote to disk; only these are
                        // the app's to clear.
                        '${kIsWeb ? ' (kept in the browser)' : ''}',
                onTap: _busy || bytes == 0 ? null : _clear,
              );
            },
          ),
          _Row(
            key: const ValueKey<String>('storage-reload-templates'),
            icon: Icons.sync_outlined,
            title: 'Reload templates',
            subtitle: 'The approved templates are kept on this device and '
                'refresh themselves when they change. Use this if one '
                'looks out of date.',
            onTap: _busy ? null : _reloadTemplates,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      // Rows under a section heading have no icon of their own; the blank
      // keeps their text on the same line as the rows above.
      leading: icon == null
          ? const SizedBox(width: 24)
          : Icon(icon, color: Wa.icon),
      title: Text(title, style: const TextStyle(color: Wa.title, fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 12.5),
            ),
    );
  }
}
