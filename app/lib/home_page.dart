import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'app_settings.dart';
import 'haptics.dart';
import 'list_page.dart';
import 'settings_page.dart';
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
  final _bankPager = PageController(); // page 0 = bank 1, page 6 = extras (700+)
  int _pageIndex = 0;
  String _query = '';
  bool _errorExpanded = false;

  @override
  void initState() {
    super.initState();
    Haptics.init();
    AppSettings.instance.load();
    _loadColors();
    controller.loadStoredList();
    controller.loadStoredVolume();
    controller.loadLastDevice();
    controller.tryAutoReconnect();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  // Run an action with a light haptic tick (used by secondary controls).
  void _haptic(VoidCallback action) {
    Haptics.light();
    action();
  }

  // Wrap a title for a key tile: max 12 chars per line, break only *before* a
  // non-lowercase character, max 3 lines, then cut off with an ellipsis.
  static String _wrapKeyTitle(String s) {
    bool isLower(String ch) {
      final c = ch.codeUnitAt(0);
      return (c >= 0x61 && c <= 0x7a) || 'äöüß'.contains(ch);
    }

    // Split into chunks; each chunk starts at a break-allowed position
    // (start of string or any non-lowercase character).
    final chunks = <String>[];
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (i > 0 && !isLower(ch)) {
        chunks.add(buf.toString());
        buf.clear();
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());

    final lines = <String>[];
    String cur = '';
    bool more = false; // content left over after 3 lines
    void pushCur() {
      if (cur.isNotEmpty) {
        lines.add(cur);
        cur = '';
      }
    }

    outer:
    for (var chunk in chunks) {
      // Hard-split a chunk that is itself longer than 12 (all lowercase run).
      while (chunk.length > 12) {
        pushCur();
        if (lines.length >= 3) {
          more = true;
          break outer;
        }
        lines.add(chunk.substring(0, 12));
        chunk = chunk.substring(12);
      }
      if (chunk.isEmpty) continue;
      if (cur.isEmpty) {
        cur = chunk;
      } else if (cur.length < 6 && cur.length + chunk.length <= 12) {
        // Only keep merging while the line is still short; once it reaches ~6
        // characters, break at the next opportunity (shorter, tidier lines).
        cur += chunk;
      } else {
        if (lines.length >= 3) {
          more = true;
          break outer;
        }
        lines.add(cur);
        cur = chunk;
      }
    }
    if (!more && cur.isNotEmpty) {
      if (lines.length < 3) {
        lines.add(cur);
      } else {
        more = true;
      }
    }
    if (more && lines.length == 3) {
      final last = lines[2];
      lines[2] = '${last.length >= 12 ? last.substring(0, 11) : last}…';
    }
    return lines.join('\n');
  }

  // Shown when the user taps a sound while not connected (otherwise nothing
  // would happen and it looks broken).
  void _notConnectedHint() {
    Haptics.light();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        content: Text('Nicht verbunden – oben aufs Bluetooth-Symbol tippen.'),
      ));
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
    _bankPager.dispose();
    controller.dispose();
    super.dispose();
  }

  // Switch bank from the chips, animating the swipe pager to match.
  void _goToBank(int b) {
    Haptics.light();
    setState(() => _pageIndex = b - 1);
    controller.setBank(b);
    _animatePager(b - 1);
  }

  void _goToExtras() {
    Haptics.light();
    setState(() => _pageIndex = 6);
    _animatePager(6);
  }

  void _animatePager(int page) {
    if (_bankPager.hasClients) {
      _bankPager.animateToPage(page,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
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
      listenable: Listenable.merge([controller, AppSettings.instance]),
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
                // Keep both tabs alive so switching away and back doesn't reset
                // the swipe page (bank) or the list scroll/search.
                children: [
                  _KeepAlive(child: _tastenTab(connected)),
                  _KeepAlive(child: _listeTab(connected)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tastenTab(bool connected) {
    // Never scroll: bank selector and controls take their natural height, the
    // grid fills the rest. Swipe horizontally to switch banks (one page each).
    return Column(
      children: [
        _bankSelector(),
        Expanded(
          // 6 bank pages + 1 "extras" page (700+ app-only tracks).
          child: PageView.builder(
            controller: _bankPager,
            itemCount: 7,
            onPageChanged: (i) {
              setState(() => _pageIndex = i);
              if (i < 6 && controller.activeBank != i + 1) {
                Haptics.light();
                controller.setBank(i + 1);
              } else if (i == 6) {
                Haptics.light();
              }
            },
            itemBuilder: (_, i) =>
                i < 6 ? _grid(connected, i + 1) : _extrasGrid(connected),
          ),
        ),
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
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Stop',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: connected ? controller.stop : null,
                  icon: const Icon(Icons.stop),
                ),
              ],
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Noch keine Liste importiert.\n\nÜber das ⋮-Menü → „Titelliste" '
                      'kannst du eine im Sorter exportierte JSON importieren.',
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
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (context, i) {
                        final t = filtered[i];
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
                            trailing: Icon(
                              playing ? Icons.graphic_eq : Icons.play_arrow,
                              color: playing ? Colors.orangeAccent : null,
                            ),
                            onTap: connected
                                ? () {
                                    controller.playNumber(t.n); // send first
                                    Haptics.medium();
                                  }
                                : _notConnectedHint,
                            onLongPress: () {
                              Haptics.light();
                              _editEntry(t);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // Long-press a list entry → edit its title (persisted, re-exportable).
  Future<void> _editEntry(TrackEntry t) async {
    final ctrl = TextEditingController(text: t.title);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Titel bearbeiten · ${t.n}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titel'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Speichern')),
        ],
      ),
    );
    if (res != null) await controller.updateTrackTitle(t.n, res.trim());
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
        item('list', Icons.queue_music, 'Titelliste'),
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
      case 'list':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ListPage(controller: controller)),
        );
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
          // 7th: extras page (700+ app-only tracks).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox(width: 46, child: _bankCell(
              selected: _pageIndex == 6,
              onTap: _goToExtras,
              child: Icon(Icons.more_horiz,
                  color: _pageIndex == 6 ? Colors.black : Colors.white70),
            )),
          ),
        ],
      ),
    );
  }

  Widget _bankButton(int b) {
    final selected = _pageIndex == b - 1;
    return _bankCell(
      selected: selected,
      onTap: () => _goToBank(b),
      child: Text(
        '${b * 100}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: selected ? 18 : 15,
          color: selected ? Colors.black : Colors.white70,
        ),
      ),
    );
  }

  Widget _bankCell({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Material(
      color: selected ? Colors.lightBlueAccent : Colors.white12,
      borderRadius: BorderRadius.circular(10),
      elevation: selected ? 4 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
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
          child: child,
        ),
      ),
    );
  }

  Widget _grid(bool connected, int bank) {
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
                  for (int col = 0; col < 5; col++) _key(vr, col, connected, bank),
              ],
            ),
          ),
        );
      },
    );
  }

  // The "extras" page (700+): app-only tracks in a scrollable 5-column grid.
  Widget _extrasGrid(bool connected) {
    final extras = controller.tracklist.where((t) => t.n >= 700).toList()
      ..sort((a, b) => a.n - b.n);
    if (extras.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Keine Zusatztitel (700+).\n\nIm Sorter Dateien in die Parkplätze legen, '
            'die Liste exportieren/übertragen – sie erscheinen dann hier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 5,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      padding: const EdgeInsets.all(8),
      childAspectRatio: 1,
      children: [for (final t in extras) _extraTile(t, connected)],
    );
  }

  Widget _extraTile(TrackEntry t, bool connected) {
    final playing = controller.playingTrack == t.n;
    return _PlayPulse(
      active: playing,
      radius: BorderRadius.circular(10),
      child: Material(
        color: const Color(0xFFcfd3e0), // neutral (no bank colour)
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: connected
              ? () {
                  controller.playNumber(t.n);
                  Haptics.medium();
                }
              : _notConnectedHint,
          onLongPress: () {
            Haptics.light();
            _editEntry(t);
          },
          child: Container(
            padding: const EdgeInsets.all(3),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_wrapKeyTitle(t.title),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.1)),
                    ),
                  ),
                ),
                Text('${t.n}',
                    style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.3),
                        fontSize: 6,
                        height: 1.0)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _key(int vr, int col, bool connected, int bank) {
    final posIndex = (4 - vr) * 5 + col; // box layout: A bottom-left .. Y top-right
    final bg = _cellColor(vr, col);
    if (posIndex == 24) {
      // The hardware Mode key has no app function – use it for "play a random
      // tone" instead. While a random track is playing, flash its number here.
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
                    controller.playRandom(); // send first
                    Haptics.medium();
                  }
                : _notConnectedHint,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              padding: const EdgeInsets.all(2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: playing
                    ? Text(
                        '${controller.playingTrack}',
                        style: const TextStyle(
                            fontSize: 22,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold),
                      )
                    : const Column(
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
    final track = bank * 100 + pos;
    final playing = controller.playingTrack == track;
    final title =
        AppSettings.instance.showTitlesOnKeys ? controller.titleOf(track) : null;
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
                  controller.playNumber(track); // send first
                  Haptics.medium();
                }
              : _notConnectedHint,
          onLongPress: () {
            Haptics.light();
            _showKeyAssignments(pos, connected);
          },
          child: Container(
            padding: const EdgeInsets.all(3),
            child: title != null
                // Title scales to fit; the number stays a fixed, uniform size.
                ? Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_wrapKeyTitle(title),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    height: 1.1)),
                          ),
                        ),
                      ),
                      Text('$track',
                          style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.3),
                              fontSize: 6,
                              height: 1.0)),
                    ],
                  )
                // Number only: one fixed size for every tile.
                : Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('$track',
                          style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Single-line status above STOP: shows the currently playing title (if known
  // from the imported list), or an error that can be expanded if it's long.
  Widget _statusLine() {
    final err = controller.errorMessage;
    if (err != null) {
      return InkWell(
        onTap: () => setState(() => _errorExpanded = !_errorExpanded),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 26),
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  err,
                  maxLines: _errorExpanded ? null : 1,
                  overflow: _errorExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
              InkWell(
                onTap: controller.clearError,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final n = controller.playingTrack;
    final title = n == null ? null : (controller.titleOf(n) ?? '$n');
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 26),
      alignment: Alignment.centerLeft,
      child: title == null
          ? const SizedBox.shrink()
          : Row(
              children: [
                const Icon(Icons.graphic_eq, size: 16, color: Colors.orangeAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
    );
  }

  // Long-press a key → show all six bank assignments for that position at once
  // (with titles from the imported list, if available); tap a row to play it.
  void _showKeyAssignments(int pos, bool connected) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // size to content, scroll if it would overflow
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Belegung Taste $pos',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Alle sechs Bänke'),
              ),
              const Divider(height: 1),
              for (int b = 1; b <= 6; b++)
                Builder(builder: (_) {
                final n = b * 100 + pos;
                final title = controller.titleOf(n);
                return ListTile(
                  dense: true,
                  leading: Text('$n',
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.bold)),
                  title: Text(title ?? '—',
                      style: title == null
                          ? const TextStyle(color: Colors.white38)
                          : null),
                  subtitle: Text(
                      title == null
                          ? 'Bank $b'
                          : 'Bank $b · lang drücken zum Bearbeiten',
                      style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: connected
                      ? () {
                          Haptics.medium();
                          controller.playNumber(n);
                          Navigator.pop(ctx);
                        }
                      : null,
                  onLongPress: title == null
                      ? null
                      : () {
                          Haptics.light();
                          Navigator.pop(ctx);
                          _editEntry(TrackEntry(n, title));
                        },
                );
              }),
            ],
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
          _statusLine(),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.shade700.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white70,
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
                  onLongPress: connected ? _showVolumeSlider : null,
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

  // Long-press the middle volume button → a horizontal slider for fine control.
  void _showVolumeSlider() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Lautstärke  ${controller.volumePct} %',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    const Icon(Icons.volume_mute, size: 20),
                    Expanded(
                      child: Slider(
                        value: controller.volumePct.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20, // 5 % steps → limits BT traffic while dragging
                        label: '${controller.volumePct} %',
                        onChanged: (v) {
                          controller.setVolumePct(v.round());
                          setSheet(() {});
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up, size: 22),
                  ],
                ),
              ],
            ),
          ),
        ),
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

/// Keeps its [child]'s state alive when scrolled off-screen in a TabBarView, so
/// the bank swipe page and list scroll position survive a tab switch.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
                  // Subtle: a thin orange outline that gently fades in/out.
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      border: Border.all(
                        color: Colors.orangeAccent
                            .withValues(alpha: 0.35 + 0.45 * t),
                        width: 1.5,
                      ),
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
