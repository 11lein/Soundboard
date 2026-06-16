import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'soundboard_controller.dart';

/// Manage the imported title list: import, export and a small summary. Reached
/// from the home page's overflow menu so the list tab itself stays clean.
class ListPage extends StatefulWidget {
  final SoundboardController controller;
  const ListPage({super.key, required this.controller});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  SoundboardController get c => widget.controller;

  Future<void> _import() async {
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
    if (content == null) return;
    final n = await c.importListFromJson(content);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n >= 0 ? '$n Titel importiert' : 'Ungültige Listendatei'),
    ));
  }

  Future<void> _export() async {
    final d = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final ts =
        '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}-${two(d.minute)}-${two(d.second)}';
    final bytes = Uint8List.fromList(utf8.encode(c.exportJson()));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Liste exportieren',
      fileName: 'soundboard-liste_$ts.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? 'Liste exportiert' : 'Export abgebrochen'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final count = c.tracklist.length;
        final hasList = count > 0;
        return Scaffold(
          appBar: AppBar(title: const Text('Titelliste')),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(hasList ? '$count Titel' : 'Keine Liste importiert'),
                subtitle: Text(c.listImportedAt != null
                    ? 'Importiert – Titel werden in der Liste und (optional) auf den Tasten angezeigt'
                    : 'Im Sorter exportieren und hier importieren'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.file_open),
                title: const Text('Liste importieren'),
                subtitle: const Text('JSON aus dem Sorter laden'),
                onTap: _import,
              ),
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
}
