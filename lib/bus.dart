import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// A person waiting for a seat.
class Waiting {
  String name;
  bool priority;

  Waiting(this.name, this.priority);

  Map<String, dynamic> toJson() {
    return {'name': name, 'priority': priority};
  }

  factory Waiting.fromJson(Map<String, dynamic> json) {
    return Waiting(json['name'] as String, json['priority'] as bool);
  }
}

class Bus {
  String route = 'Huye';
  int price = 3000;

  // 12 seats. null = free, otherwise the passenger's name.
  List<String?> seats = List.filled(12, null);

  // People waiting for a seat, in order.
  List<Waiting> waitlist = [];

  int get seatsSold => seats.where((s) => s != null).length;

  int get moneyMade => seatsSold * price;

  bool get isFull => seatsSold == seats.length;

  // Books a seat. Returns an error message, or null if it worked.
  String? book(int seat, String name) {
    name = name.trim();

    if (name.isEmpty) {
      return 'Name cannot be empty';
    }
    if (seats[seat] != null) {
      return 'This seat is already taken';
    }
    for (String? s in seats) {
      if (s != null && s.toLowerCase() == name.toLowerCase()) {
        return '$name already has a seat';
      }
    }

    seats[seat] = name;
    save();
    return null;
  }

  // Cancels a booking. If someone is waiting, they move into the seat.
  // Returns a message like "Frank moved into seat 4", or null.
  String? cancel(int seat) {
    seats[seat] = null;

    if (waitlist.isEmpty) {
      save();
      return null;
    }

    Waiting first = waitlist.removeAt(0);
    seats[seat] = first.name;
    save();
    return '${first.name} moved into seat ${seat + 1}';
  }

  // Adds someone to the waitlist.
  void joinWaitlist(String name, bool priority) {
    Waiting person = Waiting(name.trim(), priority);

    if (!priority) {
      waitlist.add(person);
      save();
      return;
    }

    // Priority: go before the first ordinary passenger.
    int position = waitlist.indexWhere((p) => !p.priority);
    if (position == -1) {
      waitlist.add(person); // nobody ordinary, go at the end
    } else {
      waitlist.insert(position, person);
    }
    save();
  }

  // Works out the change in notes, biggest first.
  // Returns null if the cash is refused.
  // Example: change(10000) -> {5000: 1, 2000: 1}
  Map<int, int>? change(int paid) {
    if (paid < price || paid % 100 != 0) {
      return null;
    }

    int rest = paid - price;
    Map<int, int> result = {};

    for (int note in [5000, 2000, 1000, 500, 100]) {
      int count = rest ~/ note;
      if (count > 0) {
        result[note] = count;
        rest = rest - count * note;
      }
    }
    return result;
  }

  // Saves the seats and the waitlist on the phone.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seats', jsonEncode(seats));
    final list = waitlist.map((p) => p.toJson()).toList();
    await prefs.setString('waitlist', jsonEncode(list));
  }

  // Loads what was saved. Returns false if nothing was saved yet.
  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSeats = prefs.getString('seats');
    final savedWaitlist = prefs.getString('waitlist');
    if (savedSeats == null) {
      return false;
    }

    final seatList = jsonDecode(savedSeats) as List;
    seats = seatList.map((s) => s as String?).toList();

    if (savedWaitlist != null) {
      final list = jsonDecode(savedWaitlist) as List;
      waitlist =
          list.map((x) => Waiting.fromJson(x as Map<String, dynamic>)).toList();
    }
    return true;
  }
}
