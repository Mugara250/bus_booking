import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_gate.dart';

void main() async {
  // Needed before using Firebase in main.
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase before the app opens.
  await Firebase.initializeApp();

  runApp(const MaterialApp(
    title: 'Bus Booking',
    debugShowCheckedModeBanner: false,
    home: AuthGate(),
  ));
}
