import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  @override
  void initState() {
    super.initState();
    _loadColors();
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
    controller.dispose();
    super.dispose();
  }

  Future<void> _pickDevice() async {
    await controller.loadDevices();
    if (!mounted) return;
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Soundboard Remote'),
            actions: [
              Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: connected ? Colors.lightBlueAccent : Colors.white54,
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _connectionBar(connected),
                _bankSelector(),
                _grid(connected),
                const SizedBox(height: 10),
                _controls(connected),
              ],
            ),
          ),
        );
      },
    );
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
        onTap: connected ? () => controller.playKey(pos) : null,
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
