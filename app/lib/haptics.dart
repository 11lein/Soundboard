import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// Real vibration feedback via the device vibrator. Unlike Flutter's
/// HapticFeedback (which the system can mute via the "touch vibration"
/// setting), this fires the motor directly using the VIBRATE permission.
///
/// User-configurable on the settings page: on/off, base intensity (amplitude)
/// and base duration. The light/medium/heavy helpers scale those values.
class Haptics {
  static bool _hasVibrator = false;
  static bool _hasAmplitude = false;

  // Configurable settings (persisted in shared_preferences).
  static bool enabled = true;
  static int amplitude = 190; // 1..255 baseline (medium)
  static int durationMs = 40; // baseline duration in ms (medium)

  static const _kEnabled = 'haptics_enabled';
  static const _kAmplitude = 'haptics_amplitude';
  static const _kDuration = 'haptics_duration';

  /// Probe the hardware and load the saved settings. Call once at startup.
  static Future<void> init() async {
    _hasVibrator = await Vibration.hasVibrator();
    if (_hasVibrator) _hasAmplitude = await Vibration.hasAmplitudeControl();
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? true;
    amplitude = p.getInt(_kAmplitude) ?? 190;
    durationMs = p.getInt(_kDuration) ?? 40;
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setInt(_kAmplitude, amplitude);
    await p.setInt(_kDuration, durationMs);
  }

  /// Whether the device actually has a vibrator (to grey out the settings).
  static bool get available => _hasVibrator;
  static bool get hasAmplitudeControl => _hasAmplitude;

  static void _buzz(double durFactor, double ampFactor) {
    if (!enabled || !_hasVibrator) return;
    final d = (durationMs * durFactor).round().clamp(5, 400);
    if (_hasAmplitude) {
      final a = (amplitude * ampFactor).round().clamp(1, 255);
      Vibration.vibrate(duration: d, amplitude: a);
    } else {
      Vibration.vibrate(duration: d);
    }
  }

  static void light() => _buzz(0.5, 0.55); // volume / bank ticks
  static void medium() => _buzz(1.0, 1.0); // playing a sound
  static void heavy() => _buzz(1.7, 1.3); // STOP

  /// Fire a sample buzz so the user can feel the current settings.
  static void test() => medium();
}
