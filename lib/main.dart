import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'bus.dart';
import 'screens.dart';

void main() async {
  // Needed before using Firebase and shared_preferences in main.
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase before the app opens.
  await Firebase.initializeApp();

  // The one bus used by the whole app.
  Bus bus = Bus();

  // Load the saved bookings. The very first time, nothing is saved,
  // so add a few sample bookings instead.
  bool found = await bus.load();
  if (!found) {
    bus.book(0, 'Alice');
    bus.book(3, 'Jean');
    bus.book(7, 'Grace');
  }

  runApp(MaterialApp(
    title: 'Bus Booking',
    debugShowCheckedModeBanner: false,
    home: SeatMapScreen(bus: bus),
  ));
}
