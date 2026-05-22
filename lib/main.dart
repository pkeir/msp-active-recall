import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/msp.dart';
import 'services/game_service.dart';
import 'screens/game_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final jsonString = await rootBundle.loadString('assets/data/msps.json');
  final jsonList = jsonDecode(jsonString) as List<dynamic>;
  final msps =
      jsonList.map((j) => Msp.fromJson(j as Map<String, dynamic>)).toList();

  final prefs = await SharedPreferences.getInstance();
  final guessedList = prefs.getStringList('guessed_msps') ?? [];
  final guessedSlugs = Set<String>.from(guessedList);

  final service = GameService(msps: msps, initialGuessed: guessedSlugs);

  runApp(MspActiveRecallApp(service: service));
}

class MspActiveRecallApp extends StatelessWidget {
  const MspActiveRecallApp({super.key, required this.service});

  final GameService service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MSP Active Recall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003087),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: GameScreen(service: service),
    );
  }
}
