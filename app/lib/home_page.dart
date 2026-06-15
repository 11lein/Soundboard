import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'haptics.dart';
import 'settings_page.dart';
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
    Haptics.init();
    _loadColors();
    controller.loadStoredList();
    controller.loadStoredVolume();
    controller.loadLastDevice();
    controller.tryAutoReconnect();
    controller.addListener(_onControllerChanged);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  // Run an action with a light haptic tick (used by secondary controls).
  void _haptic(VoidCallback action) {
    Haptics.light();
    action();
  }

  // Surface controller errors as a toast (SnackBar) and consume them, so the
  // connection bar stays a fixed layout.
  void _onControllerChanged() {
    final err = controller.errorMessage;
    if (err == null) return;
    controller.errorMessage = null; // consume once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
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
    controller.removeListener(_onControllerChanged);
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
                _btIcon(connected),
                _overflowMenu(connected),
              ],
              bottom: const TabBar(
                tabs: [Tab(text: 'Tasten'), Tab(text: 'Liste')],
              ),
            ),
            body: SafeArea(
              child: TabBarView(
                children: [_tastenTab(connected), _listeTab(connected)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tastenTab(bool connected) {
    // Never scroll: bank selector and controls take their natural height, the
    // grid fills whatever is left with square tiles that shrink to fit.
    return Column(
      children: [
        _bankSelector(),
        Expanded(child: _grid(connected)),
        _controls(connected),
      ],
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
                        final playing = controller.playingTrack == t.n;
                        return _PlayPulse(
                          active: playing,
                          radius: BorderRadius.circular(6),
                          child: ListTile(
                            dense: true,
                            tileColor:
                                playing ? Colors.orangeAccent.withValues(alpha: 0.12) : null,
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
                            trailing: Icon(
                              playing ? Icons.graphic_eq : Icons.play_arrow,
                              color: playing ? Colors.orangeAccent : null,
                            ),
                            onTap: connected
                                ? () {
                                    Haptics.medium();
                                    controller.playNumber(t.n);
                                  }
                                : null,
                          ),
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

  // Bluetooth state icon in the AppBar (refreshed by the controller's watchdog).
  // Connected → blue indicator. Disconnected → tap reconnects to the last device
  // (or opens the picker if none). Connecting → small spinner.
  Widget _btIcon(bool connected) {
    if (controller.state == ConnState.connecting) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.amberAccent)),
      );
    }
    if (connected) {
      return IconButton(
        tooltip: controller.lastDeviceName != null
            ? 'Verbunden (${controller.lastDeviceName})'
            : 'Verbunden',
        icon: const Icon(Icons.bluetooth_connected, color: Colors.lightBlueAccent),
        onPressed: () {}, // pure indicator (keeps full colour, no grey)
      );
    }
    final hasLast = controller.lastDeviceName != null;
    return IconButton(
      tooltip: hasLast ? 'Verbinden (${controller.lastDeviceName})' : 'Verbinden',
      icon: const Icon(Icons.bluetooth_disabled, color: Colors.white54),
      onPressed: () => hasLast ? controller.reconnectLast() : _pickDevice(),
    );
  }

  Widget _overflowMenu(bool connected) {
    final hasLast = controller.lastDeviceName != null;
    PopupMenuItem<String> item(String value, IconData icon, String text) =>
        PopupMenuItem<String>(
          value: value,
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(text),
          ]),
        );
    return PopupMenuButton<String>(
      tooltip: 'Menü',
      onSelected: _onMenu,
      itemBuilder: (ctx) => [
        if (connected)
          item('disconnect', Icons.link_off, 'Verbindung trennen')
        else
          item('connect', Icons.bluetooth_searching, 'Gerät verbinden…'),
        if (hasLast) item('forget', Icons.delete_outline, 'Gerät vergessen'),
        if (connected) item('restart', Icons.restart_alt, 'ESP32 neu starten'),
        const PopupMenuDivider(),
        item('settings', Icons.settings, 'Einstellungen'),
      ],
    );
  }

  void _onMenu(String value) {
    switch (value) {
      case 'disconnect':
        controller.disconnect();
        break;
      case 'connect':
        _pickDevice();
        break;
      case 'forget':
        controller.forgetDevice();
        break;
      case 'restart':
        _confirmReset();
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
    }
  }

  Widget _bankSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          for (int b = 1; b <= 6; b++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _bankButton(b),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bankButton(int b) {
    final selected = controller.activeBank == b;
    return Material(
      color: selected ? Colors.lightBlueAccent : Colors.white12,
      borderRadius: BorderRadius.circular(10),
      elevation: selected ? 4 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _haptic(() => controller.setBank(b)),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            '${b * 100}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: selected ? 18 : 15,
              color: selected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(bool connected) {
    const pad = 8.0;
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (context, c) {
        // Largest square that fits both the available width and height, so the
        // 5×5 grid never overflows (tiles shrink instead of the view scrolling).
        final side = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) - 2 * pad;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GridView.count(
              crossAxisCount: 5,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int vr = 0; vr < 5; vr++)
                  for (int col = 0; col < 5; col++) _key(vr, col, connected),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _key(int vr, int col, bool connected) {
    final posIndex = (4 - vr) * 5 + col; // box layout: A bottom-left .. Y top-right
    final bg = _cellColor(vr, col);
    if (posIndex == 24) {
      // The hardware Mode key has no app function – use it for "play a random
      // tone" instead.
      final playing = controller.playingFromRandom && controller.playingTrack != null;
      return _PlayPulse(
        active: playing,
        radius: BorderRadius.circular(10),
        child: Material(
          color: bg.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: connected
                ? () {
                    Haptics.medium();
                    controller.playRandom();
                  }
                : null,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              padding: const EdgeInsets.all(2),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎲', style: TextStyle(fontSize: 18)),
                    Text('Zufall',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.black54,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final pos = posIndex + 1; // 1..24
    final track = controller.activeBank * 100 + pos;
    final playing = controller.playingTrack == track;
    return _PlayPulse(
      active: playing,
      radius: BorderRadius.circular(10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: connected
              ? () {
                  Haptics.medium();
                  controller.playKey(pos);
                }
              : null,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$track',
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
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
            onPressed: connected
                ? () {
                    Haptics.heavy();
                    controller.stop();
                  }
                : null,
            icon: const Icon(Icons.stop),
            label: const Text('STOP'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: connected ? () => _haptic(() => controller.volumeStep(-5)) : null,
                  child: const Text('− 5 %', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: connected ? () => _haptic(() => controller.setVolumePct(100)) : null,
                  child: Text('${controller.volumePct} %',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: connected ? () => _haptic(() => controller.volumeStep(5)) : null,
                  child: const Text('+ 5 %', style: TextStyle(fontSize: 16)),
                ),
              ),
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

/// Overlays a pulsing "now playing" glow on its [child] while [active] is true.
/// The animation only runs while active (no idle controllers for every tile).
class _PlayPulse extends StatefulWidget {
  final bool active;
  final BorderRadius radius;
  final Widget child;
  const _PlayPulse({
    required this.active,
    required this.radius,
    required this.child,
  });

  @override
  State<_PlayPulse> createState() => _PlayPulseState();
}

class _PlayPulseState extends State<_PlayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PlayPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final t = Curves.easeInOut.transform(_c.value);
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      border: Border.all(
                        color: Color.lerp(Colors.orangeAccent,
                            Colors.deepOrange, t)!,
                        width: 2 + 2 * t,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withValues(alpha: 0.5 * t),
                          blurRadius: 10 * t,
                          spreadRadius: 1.5 * t,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
