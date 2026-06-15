import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A paired Bluetooth Classic device.
class BtDevice {
  final String name;
  final String address;
  BtDevice(this.name, this.address);
}

/// One entry of the imported track list: number (101..624) and title.
class TrackEntry {
  final int n;
  final String title;
  TrackEntry(this.n, this.title);
}

enum ConnState { disconnected, connecting, connected }

/// Talks to the ESP32 soundboard over Bluetooth Classic (SPP) via a native
/// platform channel. Protocol (ASCII number + '\n'):
///   101..624   -> play track (bank*100 + key)
///   7000..7100 -> set volume to (n-7000) percent (0..100)
///   9999 stop · 9995 restart
class SoundboardController extends ChangeNotifier {
  static const _ch = MethodChannel('soundboard/bt');

  ConnState state = ConnState.disconnected;
  String? deviceName;
  String status = '';
  // Transient error to surface as a toast/SnackBar (consumed once by the UI),
  // kept out of `status` so the connection bar layout never shifts.
  String? errorMessage;
  List<BtDevice> devices = [];
  int activeBank = 1; // 1..6
  // True when the BT permission was permanently denied, so the UI can offer to
  // open the system app settings (a re-request no longer shows the dialog).
  bool permissionPermanentlyDenied = false;

  // Volume in percent (0..100), mapped to the DFPlayer 0..30 range on the ESP.
  int volumePct = 100;
  static const _volumeKey = 'volume_pct';

  // Imported track list (number -> title), sorted by number.
  List<TrackEntry> tracklist = [];
  String? listImportedAt;
  static const _prefsKey = 'tracklist_json';

  // Last successfully connected device, for auto-reconnect on launch.
  static const _lastDeviceKey = 'last_device';

  // Connection watchdog: polls the native link so the status icon stays fresh,
  // and (unless the user disconnected on purpose) reconnects to the last device.
  Timer? _monitor;
  bool _userDisconnected = false;
  bool _attempting = false; // a connect attempt is in flight (guards overlap)
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  final _rng = Random();

  // Visual "now playing" feedback: the last triggered track, auto-cleared after
  // 3 s (the ESP reports no real length, so we cap the animation).
  int? playingTrack;
  bool playingFromRandom = false;
  Timer? _playTimer;
  // Name of the last device, for the reconnect button label (loaded from prefs).
  String? lastDeviceName;

  SoundboardController() {
    _ch.setMethodCallHandler(_onNative);
    _startMonitor();
  }

  @override
  void dispose() {
    _monitor?.cancel();
    _playTimer?.cancel();
    super.dispose();
  }

  void _markPlaying(int n, {bool fromRandom = false}) {
    errorMessage = null; // a successful action clears any stale error
    playingTrack = n;
    playingFromRandom = fromRandom;
    notifyListeners();
    _playTimer?.cancel();
    _playTimer = Timer(const Duration(seconds: 3), () {
      playingTrack = null;
      playingFromRandom = false;
      notifyListeners();
    });
  }

  void _clearPlaying() {
    _playTimer?.cancel();
    playingTrack = null;
    playingFromRandom = false;
    notifyListeners();
  }

  /// Dismiss the current error shown in the status line.
  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// Title of a track number from the imported list, or null if unknown.
  String? titleOf(int n) {
    for (final t in tracklist) {
      if (t.n == n) return t.title;
    }
    return null;
  }

  void _startMonitor() {
    _monitor?.cancel();
    // Poll quickly so the connection icon reflects reality within ~1 s. Real
    // drops are also pushed immediately from the native reader (onNative).
    _monitor = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      bool alive = false;
      try {
        alive = await _ch.invokeMethod('isConnected') == true;
      } catch (_) {
        alive = false;
      }
      if (alive) {
        if (state != ConnState.connected) {
          state = ConnState.connected;
          notifyListeners();
        }
        return;
      }
      // Native link is down.
      if (state == ConnState.connected) {
        // We thought we were connected → the link dropped.
        state = ConnState.disconnected;
        status = 'Verbindung verloren';
        notifyListeners();
      }
      // Auto-reconnect to the last device only (never another one), unless the
      // user disconnected deliberately or a connect attempt is already running.
      if (!_userDisconnected && state == ConnState.disconnected) {
        reconnectLast(silent: true);
      }
    });
  }

  /// Load the last device's name from prefs (for the reconnect button label).
  Future<void> loadLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_lastDeviceKey);
    if (stored == null) return;
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      lastDeviceName = (m['name'] ?? '').toString();
      notifyListeners();
    } catch (_) {/* ignore */}
  }

  /// Reconnect to the last stored device only. No device picker, no fallback.
  /// `silent` (used by the watchdog) suppresses the failure status text.
  Future<void> reconnectLast({bool silent = false}) async {
    if (_attempting) return;
    // Throttle silent background retries so the UI never rapidly oscillates.
    if (silent &&
        DateTime.now().difference(_lastAttempt) < const Duration(seconds: 3)) {
      return;
    }
    // Silent (watchdog) path must never pop a permission dialog – just check.
    if (silent) {
      if (!(await Permission.bluetoothConnect.status).isGranted) return;
    } else if (!await ensureBtPermission()) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_lastDeviceKey);
    if (stored == null) return;
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      final address = (m['address'] ?? '').toString();
      final name = (m['name'] ?? '').toString();
      if (address.isEmpty) return;
      await connect(BtDevice(name, address), silent: silent);
    } catch (_) {
      /* ignore – will retry on the next tick */
    }
  }

  /// Try to reconnect to the device used last time. Silent if none stored or
  /// the device is not reachable (the user can still connect manually).
  Future<void> tryAutoReconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_lastDeviceKey);
    if (stored == null) return;
    String name, address;
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      name = (m['name'] ?? '').toString();
      address = (m['address'] ?? '').toString();
    } catch (_) {
      return;
    }
    if (address.isEmpty) return;
    // Don't pop a permission dialog on launch: only auto-reconnect if the user
    // has already granted Bluetooth. Otherwise wait until they tap "Verbinden".
    if (!(await Permission.bluetoothConnect.status).isGranted) return;
    await loadDevices();
    // Only reconnect if the device is still paired.
    if (!devices.any((d) => d.address == address)) return;
    await connect(BtDevice(name, address));
  }

  // ---- Imported track list ----
  Future<void> loadStoredList() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null) _parseList(json);
    notifyListeners();
  }

  /// Import a list exported by the sorter (JSON). Returns the entry count.
  Future<int> importListFromJson(String json) async {
    final n = _parseList(json);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json);
    notifyListeners();
    return n;
  }

  int _parseList(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final list = (data['tracks'] as List)
          .map((e) => TrackEntry((e['n'] as num).toInt(), (e['title'] ?? '').toString()))
          .toList()
        ..sort((a, b) => a.n - b.n);
      tracklist = list;
      listImportedAt = data['exported'] as String?;
      return list.length;
    } catch (_) {
      return -1; // invalid file
    }
  }

  /// Edit a single title and persist the updated list (so it survives and can
  /// be re-exported for renaming in the sorter).
  Future<void> updateTrackTitle(int n, String title) async {
    final i = tracklist.indexWhere((t) => t.n == n);
    if (i < 0) return;
    tracklist[i] = TrackEntry(n, title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, exportJson());
    notifyListeners();
  }

  /// Serialize the current list in the same JSON format the sorter uses, so it
  /// can be re-imported there for file renaming.
  String exportJson() {
    final tracks = [
      for (final t in tracklist) {'n': t.n, 'title': t.title}
    ];
    return jsonEncode({
      'exported': DateTime.now().toIso8601String(),
      'count': tracks.length,
      'tracks': tracks,
    });
  }

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'disconnected') {
      state = ConnState.disconnected;
      status = 'Verbindung getrennt';
      notifyListeners();
    }
  }

  /// Make sure BLUETOOTH_CONNECT is granted before any native BT call.
  /// Android 12+ (API 31) requires it at runtime; older versions grant it at
  /// install time, so the request resolves to "granted" immediately there.
  /// Returns true only if the app may use Bluetooth now.
  Future<bool> ensureBtPermission() async {
    var st = await Permission.bluetoothConnect.status;
    if (st.isGranted) {
      permissionPermanentlyDenied = false;
      return true;
    }
    // Not granted yet → ask (shows the system dialog unless already blocked).
    st = await Permission.bluetoothConnect.request();
    permissionPermanentlyDenied = st.isPermanentlyDenied;
    if (st.isGranted) return true;
    errorMessage = permissionPermanentlyDenied
        ? 'Bluetooth-Berechtigung dauerhaft abgelehnt – bitte in den '
            'App-Einstellungen erlauben.'
        : 'Bluetooth-Berechtigung wird benötigt, um Geräte zu finden.';
    notifyListeners();
    return false;
  }

  /// Open the system app-settings page so the user can grant a permission that
  /// was permanently denied.
  Future<void> openSettings() => openAppSettings();

  Future<void> loadDevices() async {
    if (!await ensureBtPermission()) return;
    try {
      final List list = await _ch.invokeMethod('bondedDevices');
      devices = [
        for (final e in list)
          BtDevice((e['name'] as String?) ?? '', e['address'] as String)
      ];
      status = '${devices.length} gekoppelte Geräte';
    } on PlatformException catch (e) {
      errorMessage = 'Fehler: ${e.message}';
    }
    notifyListeners();
  }

  Future<void> connect(BtDevice d, {bool silent = false}) async {
    if (_attempting) return;
    _attempting = true;
    _lastAttempt = DateTime.now();
    _userDisconnected = false;
    deviceName = d.name;
    // Only a user-initiated connect shows the "Verbinde…" state. Silent
    // background retries keep the visible state untouched (no flicker).
    if (!silent) {
      state = ConnState.connecting;
      status = 'Verbinde mit ${d.name}…';
      notifyListeners();
    }
    try {
      await _ch.invokeMethod('connect', {'address': d.address});
      state = ConnState.connected;
      status = 'Verbunden mit ${d.name}';
      errorMessage = null;
      // Remember this device for auto-reconnect next launch.
      lastDeviceName = d.name;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastDeviceKey, jsonEncode({'name': d.name, 'address': d.address}));
      // Push the app's current volume so the ESP matches what the UI shows.
      await _send(7000 + volumePct);
    } on PlatformException catch (e) {
      state = ConnState.disconnected;
      if (!silent) errorMessage = 'Verbindung fehlgeschlagen: ${e.message}';
    } finally {
      _attempting = false;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _userDisconnected = true; // suppress auto-reconnect until the user reconnects
    try {
      await _ch.invokeMethod('disconnect');
    } on PlatformException {
      // ignore
    }
    state = ConnState.disconnected;
    status = 'Getrennt';
    notifyListeners();
  }

  /// Disconnect (if needed) and forget the stored device, so the watchdog will
  /// not auto-reconnect to it until the user picks a device again.
  Future<void> forgetDevice() async {
    _userDisconnected = true;
    if (state != ConnState.disconnected) {
      try {
        await _ch.invokeMethod('disconnect');
      } on PlatformException {/* ignore */}
    }
    state = ConnState.disconnected;
    lastDeviceName = null;
    deviceName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastDeviceKey);
    status = 'Gerät vergessen';
    notifyListeners();
  }

  Future<void> _send(int code) async {
    if (state != ConnState.connected) {
      status = 'Nicht verbunden';
      notifyListeners();
      return;
    }
    try {
      await _ch.invokeMethod('send', {'data': '$code\n'});
    } on PlatformException catch (e) {
      errorMessage = 'Sendefehler: ${e.message}';
      state = ConnState.disconnected;
      notifyListeners();
    }
  }

  void setBank(int bank) {
    activeBank = bank;
    notifyListeners();
  }

  // ---- Volume (percent 0..100) ----
  Future<void> loadStoredVolume() async {
    final prefs = await SharedPreferences.getInstance();
    volumePct = prefs.getInt(_volumeKey) ?? 100;
    notifyListeners();
  }

  /// Set the absolute volume in percent and send it to the ESP (7000 + pct).
  Future<void> setVolumePct(int pct) async {
    volumePct = pct.clamp(0, 100);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_volumeKey, volumePct);
    await _send(7000 + volumePct);
  }

  /// Adjust the volume by a relative percentage (e.g. +5 / -5).
  Future<void> volumeStep(int delta) => setVolumePct(volumePct + delta);

  // Note: always fire _send() *before* _markPlaying(). _markPlaying triggers a
  // synchronous UI rebuild (notifyListeners); doing it first would delay the
  // Bluetooth command by a few milliseconds. Send first, animate after.
  Future<void> playKey(int pos) {
    final n = activeBank * 100 + pos; // pos 1..24
    final f = _send(n);
    _markPlaying(n);
    return f;
  }

  Future<void> playNumber(int n) {
    final f = _send(n); // absolute track 101..624
    _markPlaying(n);
    return f;
  }

  /// Play a random tone. Prefers the imported track list (real, named tracks);
  /// otherwise picks a random position in the active bank.
  Future<void> playRandom() {
    final n = tracklist.isNotEmpty
        ? tracklist[_rng.nextInt(tracklist.length)].n
        : activeBank * 100 + (1 + _rng.nextInt(24));
    final f = _send(n);
    _markPlaying(n, fromRandom: true);
    return f;
  }

  Future<void> stop() {
    final f = _send(9999);
    _clearPlaying();
    return f;
  }
  Future<void> reset() => _send(9995);
}
