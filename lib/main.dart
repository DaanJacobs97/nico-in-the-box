import 'package:flutter/material.dart';

void main() {
  runApp(const NicoInTheBoxApp());
}

class NicoInTheBoxApp extends StatelessWidget {
  const NicoInTheBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nico in the Box',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Scaffold(body: Center(child: Text('Nico in the Box'))),
    );
  }
}
