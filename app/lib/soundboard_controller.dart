import 'dart:convert';
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
///   101..624 -> play track (bank*100 + key)
///   9999 stop · 9998/9997/9996 volume 10/20/30 · 9995 restart
class SoundboardController extends ChangeNotifier {
  static const _ch = MethodChannel('soundboard/bt');

  ConnState state = ConnState.disconnected;
  String? deviceName;
  String status = '';
  List<BtDevice> devices = [];
  int activeBank = 1; // 1..6

  // Imported track list (number -> title), sorted by number.
  List<TrackEntry> tracklist = [];
  String? listImportedAt;
  static const _prefsKey = 'tracklist_json';

  SoundboardController() {
    _ch.setMethodCallHandler(_onNative);
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

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'disconnected') {
      state = ConnState.disconnected;
      status = 'Verbindung getrennt';
      notifyListeners();
    }
  }

  Future<void> loadDevices() async {
    // Android 12+ needs BLUETOOTH_CONNECT at runtime; no-op on older versions.
    await Permission.bluetoothConnect.request();
    try {
      final List list = await _ch.invokeMethod('bondedDevices');
      devices = [
        for (final e in list)
          BtDevice((e['name'] as String?) ?? '', e['address'] as String)
      ];
      status = '${devices.length} gekoppelte Geräte';
    } on PlatformException catch (e) {
      status = 'Fehler: ${e.message}';
    }
    notifyListeners();
  }

  Future<void> connect(BtDevice d) async {
    state = ConnState.connecting;
    deviceName = d.name;
    status = 'Verbinde mit ${d.name}…';
    notifyListeners();
    try {
      await _ch.invokeMethod('connect', {'address': d.address});
      state = ConnState.connected;
      status = 'Verbunden mit ${d.name}';
    } on PlatformException catch (e) {
      state = ConnState.disconnected;
      status = 'Verbindung fehlgeschlagen: ${e.message}';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      await _ch.invokeMethod('disconnect');
    } on PlatformException {
      // ignore
    }
    state = ConnState.disconnected;
    status = 'Getrennt';
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
      status = 'Sendefehler: ${e.message}';
      state = ConnState.disconnected;
      notifyListeners();
    }
  }

  void setBank(int bank) {
    activeBank = bank;
    notifyListeners();
  }

  Future<void> playKey(int pos) => _send(activeBank * 100 + pos); // pos 1..24
  Future<void> playNumber(int n) => _send(n); // absolute track 101..624
  Future<void> stop() => _send(9999);
  Future<void> volume(int level) =>
      _send(level == 10 ? 9998 : (level == 20 ? 9997 : 9996));
  Future<void> reset() => _send(9995);
}
