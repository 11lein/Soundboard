import 'package:flutter/material.dart';
import 'haptics.dart';

/// Settings screen. Currently: configure the haptic (vibration) feedback.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _enabled = Haptics.enabled;
  double _amp = Haptics.amplitude.toDouble();
  double _dur = Haptics.durationMs.toDouble();

  void _persist() => Haptics.save();

  @override
  Widget build(BuildContext context) {
    final hasVibrator = Haptics.available;
    final canConfigure = _enabled && hasVibrator;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Haptisches Feedback',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          SwitchListTile(
            title: const Text('Vibration aktiviert'),
            subtitle: Text(hasVibrator
                ? 'Vibriert beim Tippen (unabhängig von der System-Einstellung)'
                : 'Dieses Gerät hat keinen Vibrationsmotor'),
            value: _enabled && hasVibrator,
            onChanged: hasVibrator
                ? (v) {
                    setState(() => _enabled = v);
                    Haptics.enabled = v;
                    _persist();
                    if (v) Haptics.test();
                  }
                : null,
          ),
          const Divider(),
          ListTile(
            title: const Text('Intensität'),
            subtitle: Text(Haptics.hasAmplitudeControl
                ? '${((_amp / 255) * 100).round()} %'
                : 'Dieses Gerät unterstützt keine Intensitäts-Steuerung'),
            enabled: canConfigure && Haptics.hasAmplitudeControl,
          ),
          Slider(
            min: 1,
            max: 255,
            divisions: 254,
            value: _amp.clamp(1, 255),
            label: '${((_amp / 255) * 100).round()} %',
            onChanged: canConfigure && Haptics.hasAmplitudeControl
                ? (v) {
                    setState(() => _amp = v);
                    Haptics.amplitude = v.round();
                  }
                : null,
            onChangeEnd: (_) {
              _persist();
              Haptics.test();
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Dauer'),
            subtitle: Text('${_dur.round()} ms'),
            enabled: canConfigure,
          ),
          Slider(
            min: 5,
            max: 150,
            divisions: 29,
            value: _dur.clamp(5, 150),
            label: '${_dur.round()} ms',
            onChanged: canConfigure
                ? (v) {
                    setState(() => _dur = v);
                    Haptics.durationMs = v.round();
                  }
                : null,
            onChangeEnd: (_) {
              _persist();
              Haptics.test();
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: canConfigure ? Haptics.test : null,
              icon: const Icon(Icons.vibration),
              label: const Text('Testen'),
            ),
          ),
        ],
      ),
    );
  }
}
