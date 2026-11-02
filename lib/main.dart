import 'package:flutter/material.dart';

import 'bus.dart';
import 'screens.dart';

void main() async {
  // Needed before using shared_preferences in main.
  WidgetsFlutterBinding.ensureInitialized();

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
