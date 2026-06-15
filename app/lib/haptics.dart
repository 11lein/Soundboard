import 'package:vibration/vibration.dart';

/// Real vibration feedback via the device vibrator. Unlike Flutter's
/// HapticFeedback (which the system can mute via the "touch vibration"
/// setting), this fires the motor directly using the VIBRATE permission.
///
/// Call [init] once at startup to probe the hardware; the [light]/[medium]/
/// [heavy] helpers are then cheap fire-and-forget calls.
class Haptics {
  static bool _hasVibrator = false;
  static bool _hasAmplitude = false;

  static Future<void> init() async {
    _hasVibrator = await Vibration.hasVibrator();
    if (_hasVibrator) {
      _hasAmplitude = await Vibration.hasAmplitudeControl();
    }
  }

  static void _buzz(int duration, int amplitude) {
    if (!_hasVibrator) return;
    if (_hasAmplitude) {
      Vibration.vibrate(duration: duration, amplitude: amplitude);
    } else {
      Vibration.vibrate(duration: duration);
    }
  }

  static void light() => _buzz(18, 110); // volume / bank ticks
  static void medium() => _buzz(38, 190); // playing a sound
  static void heavy() => _buzz(70, 255); // STOP
}
