import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:file_picker/file_picker.dart';
import 'soundboard_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final controller = SoundboardController();
  List<List<String>> _rows = [];
  Map<String, dynamic> _palette = {};
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadColors();
    controller.loadStoredList();
    controller.tryAutoReconnect();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  Future<void> _loadColors() async {
    final raw = await rootBundle.loadString('assets/key-colors.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _palette = data['palette'] as Map<String, dynamic>;
      _rows = [
        for (final r in (data['rows'] as List))
          [for (final c in (r as List)) c as String]
      ];
    });
  }

  Color _cellColor(int vr, int col) {
    if (_rows.isEmpty) return const Color(0xFFCCCCCC);
    final name = _rows[vr][col];
    final hex = _palette[name]['bg'] as String;
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _pickDevice() async {
    await controller.loadDevices();
    if (!mounted) return;
    // Permission was permanently denied → guide the user to the app settings.
    if (controller.permissionPermanentlyDenied) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bluetooth-Berechtigung fehlt',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text(
                    'Die App braucht die Berechtigung „Geräte in der Nähe" '
                    '(Bluetooth), um das Soundboard zu finden und zu verbinden. '
                    'Sie wurde dauerhaft abgelehnt – bitte in den App-Einstellungen '
                    'unter „Berechtigungen" erlauben.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    controller.openSettings();
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('App-Einstellungen öffnen'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Gekoppeltes Gerät wählen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final d in controller.devices)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name.isEmpty ? '(unbenannt)' : d.name),
                subtitle: Text(d.address),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.connect(d);
                },
              ),
            if (controller.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Keine gekoppelten Geräte. Koppel das Soundboard zuerst in den '
                    'Android-Bluetooth-Einstellungen (das_11lein).'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final connected = controller.state == ConnState.connected;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Soundboard Remote'),
              actions: [
                Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: connected ? Colors.lightBlueAccent : Colors.white54,
                ),
                const SizedBox(width: 12),
              ],
              bottom: const TabBar(
                tabs: [Tab(text: 'Tasten'), Tab(text: 'Liste')],
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _connectionBar(connected),
                  Expanded(
                    child: TabBarView(
                      children: [_tastenTab(connected), _listeTab(connected)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tastenTab(bool connected) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _bankSelector(),
          _grid(connected),
          const SizedBox(height: 10),
          _controls(connected),
        ],
      ),
    );
  }

  Widget _listeTab(bool connected) {
    final list = controller.tracklist;
    final filtered = _query.isEmpty
        ? list
        : list
            .where((t) =>
                t.title.toLowerCase().contains(_query) ||
                t.n.toString().contains(_query))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _importList,
                icon: const Icon(Icons.file_open),
                label: const Text('Liste importieren'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.listImportedAt != null
                      ? '${list.length} Titel · importiert'
                      : 'Keine Liste importiert',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (list.isNotEmpty)
                OutlinedButton(
                  onPressed: connected ? controller.stop : null,
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Titel oder Nummer suchen…',
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _searchCtrl.clear,
                      ),
              ),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Noch keine Liste importiert.\n\nIm Sorter „📋 Liste" exportieren, '
                      'die JSON-Datei aufs Handy übertragen und hier importieren.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? const Center(
                      child: Text('Kein Treffer',
                          style: TextStyle(color: Colors.white60)),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (context, i) {
                        final t = filtered[i];
                        final bank = t.n ~/ 100;
                        final pos = t.n % 100;
                        return ListTile(
                          dense: true,
                          leading: Text(
                            t.n.toString(),
                            style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          title: Text(t.title),
                          subtitle: Text(
                            'Bank $bank · Taste ${pos.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: connected
                              ? () {
                                  HapticFeedback.selectionClick();
                                  controller.playNumber(t.n);
                                }
                              : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _importList() async {
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
    final n = await controller.importListFromJson(content);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n >= 0 ? '$n Titel importiert' : 'Ungültige Listendatei'),
    ));
  }

  Widget _connectionBar(bool connected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black26,
      child: Row(
        children: [
          Expanded(
            child: Text(controller.status.isEmpty
                ? (connected ? 'Verbunden' : 'Nicht verbunden')
                : controller.status),
          ),
          if (controller.state == ConnState.connecting)
            const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (connected)
            TextButton.icon(
                onPressed: controller.disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Trennen'))
          else
            FilledButton.icon(
                onPressed: _pickDevice,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Verbinden')),
        ],
      ),
    );
  }

  Widget _bankSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Text('Bank', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (int b = 1; b <= 6; b++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Text('$b', style: const TextStyle(fontWeight: FontWeight.bold)),
                  labelPadding: EdgeInsets.zero,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: controller.activeBank == b,
                  onSelected: (_) => controller.setBank(b),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(bool connected) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (int vr = 0; vr < 5; vr++)
            for (int col = 0; col < 5; col++) _key(vr, col, connected),
        ],
      ),
    );
  }

  Widget _key(int vr, int col, bool connected) {
    final posIndex = (4 - vr) * 5 + col; // box layout: A bottom-left .. Y top-right
    final bg = _cellColor(vr, col);
    if (posIndex == 24) {
      return Container(
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        alignment: Alignment.center,
        child: const Text('MODE',
            style: TextStyle(
                fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
      );
    }
    final pos = posIndex + 1; // 1..24
    final track = controller.activeBank * 100 + pos;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: connected
            ? () {
                HapticFeedback.selectionClick();
                controller.playKey(pos);
              }
            : null,
        child: Container(
          alignment: Alignment.center,
          child: Text('$track',
              style: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _controls(bool connected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      color: Colors.black26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                minimumSize: const Size.fromHeight(48)),
            onPressed: connected ? controller.stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('STOP'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: connected ? () => controller.volume(10) : null,
                      child: const Text('Vol 10'))),
              const SizedBox(width: 6),
              Expanded(
                  child: OutlinedButton(
                      onPressed: connected ? () => controller.volume(20) : null,
                      child: const Text('Vol 20'))),
              const SizedBox(width: 6),
              Expanded(
                  child: OutlinedButton(
                      onPressed: connected ? () => controller.volume(30) : null,
                      child: const Text('Vol 30'))),
              const SizedBox(width: 6),
              Expanded(
                  child: OutlinedButton(
                      onPressed: connected ? _confirmReset : null,
                      child: const Icon(Icons.restart_alt, size: 18))),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neustart'),
        content: const Text('Das Soundboard (ESP32) neu starten?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Neustart')),
        ],
      ),
    );
    if (ok == true) controller.reset();
  }
}
