import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// App-wide UI preferences (non-haptic). A small ChangeNotifier singleton so the
/// home page can rebuild when a setting changes on the settings page.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  bool showTitlesOnKeys = false; // show the title on each key (if a list exists)
  bool keepScreenOn = false; // keep the display awake (default off)

  static const _kTitles = 'show_titles_on_keys';
  static const _kKeepAwake = 'keep_screen_on';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    showTitlesOnKeys = p.getBool(_kTitles) ?? false;
    keepScreenOn = p.getBool(_kKeepAwake) ?? false;
    await WakelockPlus.toggle(enable: keepScreenOn);
    notifyListeners();
  }

  Future<void> setShowTitlesOnKeys(bool v) async {
    showTitlesOnKeys = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTitles, v);
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v;
    notifyListeners();
    await WakelockPlus.toggle(enable: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKeepAwake, v);
  }
}
