import 'package:flutter/material.dart';
import 'home_page.dart';

void main() => runApp(const SoundboardApp());

class SoundboardApp extends StatelessWidget {
  const SoundboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soundboard Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
