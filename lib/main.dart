import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const NicoInTheBoxApp());
}

class NicoInTheBoxApp extends StatelessWidget {
  const NicoInTheBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: brightness,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );

    return MaterialApp(
      title: 'Nico in the Box',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
