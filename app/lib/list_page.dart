import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'soundboard_controller.dart';

/// Manage the imported title list: import (from the app's bundled copy or a
/// file) with a diff preview, export, and a small summary. Reached from the
/// home page's overflow menu so the list tab itself stays clean.
class ListPage extends StatefulWidget {
  final SoundboardController controller;
  const ListPage({super.key, required this.controller});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  SoundboardController get c => widget.controller;

  // The list bundled with the app (written by the sorter on export, baked in at
  // build time). null while loading; count 0 means "none bundled".
  String? _bundledJson;
  int _bundledCount = 0;
  String? _bundledExported;

  @override
  void initState() {
    super.initState();
    _loadBundled();
  }

  Future<void> _loadBundled() async {
    try {
      final raw = await rootBundle.loadString('assets/tracklist.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (data['tracks'] as List?) ?? [];
      setState(() {
        _bundledJson = tracks.isEmpty ? null : raw;
        _bundledCount = tracks.length;
        _bundledExported = data['exported'] as String?;
      });
    } catch (_) {
      setState(() => _bundledJson = null);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _importFromFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    String? content;
    if (f.bytes != null) {
      content = utf8.decode(f.bytes!);
    } else if (f.path != null) {
      content = await File(f.path!).readAsString();
    }
    if (content != null) await _previewAndImport(content);
  }

  Future<void> _export() async {
    final d = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final ts =
        '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}-${two(d.minute)}-${two(d.second)}';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Liste exportieren',
      fileName: 'soundboard-liste_$ts.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(c.exportJson()),
    );
    _toast(path != null ? 'Liste exportiert' : 'Export abgebrochen');
  }

  // Show a diff (added / changed / removed) of the to-be-imported list against
  // the current one, and only import after the user confirms.
  Future<void> _previewAndImport(String json) async {
    final incoming = c.parseTracks(json);
    if (incoming == null) {
      _toast('Ungültige Listendatei');
      return;
    }
    final old = {for (final t in c.tracklist) t.n: t.title};
    final neu = {for (final t in incoming) t.n: t.title};
    final added = incoming.where((t) => !old.containsKey(t.n)).toList();
    final removed = c.tracklist.where((t) => !neu.containsKey(t.n)).toList();
    final changed = incoming
        .where((t) => old.containsKey(t.n) && old[t.n] != t.title)
        .toList();

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${incoming.length} Titel importieren?'),
        content: SizedBox(
          width: double.maxFinite,
          child: (added.isEmpty && changed.isEmpty && removed.isEmpty)
              ? const Text('Keine Änderungen gegenüber der aktuellen Liste.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      '${added.length} neu · ${changed.length} geändert · ${removed.length} entfernt',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final t in changed)
                      _diffRow('~', '${t.n}', '${old[t.n]}  →  ${t.title}',
                          Colors.orangeAccent),
                    for (final t in added)
                      _diffRow('+', '${t.n}', t.title, Colors.greenAccent),
                    for (final t in removed)
                      _diffRow('−', '${t.n}', t.title, Colors.redAccent),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importieren')),
        ],
      ),
    );
    if (ok == true) {
      final n = await c.importListFromJson(json);
      _toast(n >= 0 ? '$n Titel importiert' : 'Import fehlgeschlagen');
    }
  }

  Widget _diffRow(String sign, String n, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 14,
              child: Text(sign,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          SizedBox(
              width: 38,
              child: Text(n,
                  style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontFeatures: [FontFeature.tabularFigures()]))),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final count = c.tracklist.length;
        final hasList = count > 0;
        final hasBundled = _bundledJson != null && _bundledCount > 0;
        return Scaffold(
          appBar: AppBar(title: const Text('Titelliste')),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(hasList ? '$count Titel geladen' : 'Keine Liste geladen'),
                subtitle: Text(c.listImportedAt != null
                    ? 'Wird in der Liste und (optional) auf den Tasten angezeigt'
                    : 'Mitgelieferte Liste übernehmen oder Datei importieren'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.smartphone),
                title: const Text('Mitgelieferte Liste übernehmen'),
                subtitle: Text(hasBundled
                    ? '$_bundledCount Titel'
                        '${_bundledExported != null ? ' · exportiert ${_fmtDate(_bundledExported!)}' : ''}'
                    : 'Keine Liste mit der App mitgeliefert'),
                trailing: const Icon(Icons.chevron_right),
                enabled: hasBundled,
                onTap: hasBundled ? () => _previewAndImport(_bundledJson!) : null,
              ),
              ListTile(
                leading: const Icon(Icons.file_open),
                title: const Text('Aus Datei importieren'),
                subtitle: const Text('JSON aus dem Sorter laden'),
                onTap: _importFromFile,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Liste exportieren'),
                subtitle: const Text(
                    'Als JSON speichern – im Sorter zum Umbenennen wiederverwendbar'),
                enabled: hasList,
                onTap: hasList ? _export : null,
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
