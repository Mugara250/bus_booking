import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String route = 'Huye';
const int price = 3000;
const int seatCount = 12;

// Ask the server, not the phone's copy: the rules below need fresh data,
// and with no internet this fails straight away instead of waiting forever.
const fromServer = GetOptions(source: Source.server);

// One booked seat. seat 0 is shown on screen as "Seat 1".
class Booking {
  Booking({required this.seat, required this.name, required this.cash});

  final int seat;
  final String name;
  final int cash;

  Map<String, dynamic> toMap() => {'seat': seat, 'name': name, 'cash': cash};

  factory Booking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Booking(
      seat: (data['seat'] as num).toInt(),
      name: data['name'] as String,
      cash: (data['cash'] as num).toInt(),
    );
  }
}

// A person waiting for a seat.
class Waiting {
  Waiting({this.id = '', required this.name, required this.priority});

  final String id;
  final String name;
  final bool priority;

  Map<String, dynamic> toMap() => {'name': name, 'priority': priority};

  factory Waiting.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Waiting(
      id: doc.id,
      name: data['name'] as String,
      priority: data['priority'] as bool,
    );
  }
}

// The signed-in user's bookings: users/{uid}/bookings
CollectionReference<Map<String, dynamic>> myBookings() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('bookings');
}

// The signed-in user's waitlist: users/{uid}/waitlist
CollectionReference<Map<String, dynamic>> myWaitlist() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('waitlist');
}

// The bus, worked out from the saved bookings. Nothing here is saved.
class Bus {
  // 12 seats. null = free, otherwise the passenger's name.
  List<String?> seats = List.filled(seatCount, null);

  Bus(List<Booking> bookings) {
    for (Booking b in bookings) {
      seats[b.seat] = b.name;
    }
  }

  int get seatsSold => seats.where((s) => s != null).length;

  int get moneyMade => seatsSold * price;

  bool get isFull => seatsSold == seats.length;
}

// Puts people in waitlist order. They must arrive in the order they joined.
List<Waiting> inOrder(List<Waiting> people) {
  List<Waiting> result = [];

  for (Waiting person in people) {
    // Priority: go before the first ordinary passenger.
    int position = result.indexWhere((p) => !p.priority);
    if (!person.priority || position == -1) {
      result.add(person); // ordinary, or nobody ordinary: go at the end
    } else {
      result.insert(position, person);
    }
  }
  return result;
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

// True if this name already has a seat (leave out one seat when editing it).
Future<bool> hasSeat(String name, {int? except}) async {
  final bookings = await myBookings().get(fromServer);
  return bookings.docs.map(Booking.fromDoc).any(
        (b) =>
            b.seat != except && b.name.toLowerCase() == name.toLowerCase(),
      );
}

// Books a seat. Returns an error message, or null if it worked.
Future<String?> book(int seat, String name, int cash) async {
  name = name.trim();

  if (name.isEmpty) {
    return 'Name cannot be empty';
  }
  if (await hasSeat(name)) {
    return '$name already has a seat';
  }

  // A transaction checks and writes in one step, so a taken seat
  // can never be booked twice, even from two phones at the same moment.
  final doc = myBookings().doc('$seat');
  return FirebaseFirestore.instance.runTransaction<String?>((transaction) async {
    final current = await transaction.get(doc);
    if (current.exists) {
      return 'This seat is already taken';
    }
    transaction.set(doc, Booking(seat: seat, name: name, cash: cash).toMap());
    return null;
  });
}

// Changes the name on a booking. Returns an error message, or null if it worked.
Future<String?> rename(int seat, String name) async {
  name = name.trim();

  if (name.isEmpty) {
    return 'Name cannot be empty';
  }
  if (await hasSeat(name, except: seat)) {
    return '$name already has a seat';
  }

  await myBookings().doc('$seat').update({'name': name});
  return null;
}

// Cancels a booking. If someone is waiting, they move into the seat.
// Returns a message like "Frank moved into seat 4", or null.
Future<String?> cancel(int seat) async {
  final waiting = await myWaitlist().orderBy('joinedAt').get(fromServer);
  final people = inOrder(waiting.docs.map(Waiting.fromDoc).toList());
  final doc = myBookings().doc('$seat');

  if (people.isEmpty) {
    await doc.delete();
    return null;
  }

  // Both writes happen together: all of them, or none.
  // The new passenger pays the normal price.
  Waiting first = people.first;
  final batch = FirebaseFirestore.instance.batch();
  batch.set(doc, Booking(seat: seat, name: first.name, cash: price).toMap());
  batch.delete(myWaitlist().doc(first.id));
  await batch.commit();
  return '${first.name} moved into seat ${seat + 1}';
}

// Adds someone to the waitlist. Returns an error message, or null if it worked.
Future<String?> joinWaitlist(String name, bool priority) async {
  name = name.trim();

  if (name.isEmpty) {
    return 'Name cannot be empty';
  }

  final bookings = await myBookings().get(fromServer);
  if (bookings.docs.length < seatCount) {
    return 'There are still free seats';
  }
  if (await hasSeat(name)) {
    return '$name already has a seat';
  }

  final waiting = await myWaitlist().get(fromServer);
  final taken = waiting.docs.map(Waiting.fromDoc).any(
        (p) => p.name.toLowerCase() == name.toLowerCase(),
      );
  if (taken) {
    return '$name is already waiting';
  }

  await myWaitlist().add({
    ...Waiting(name: name, priority: priority).toMap(),
    'joinedAt': FieldValue.serverTimestamp(),
  });
  return null;
}

// Sample data, written once when a new account is created.
Future<void> addSampleBookings() async {
  final samples = [
    Booking(seat: 0, name: 'Alice', cash: price),
    Booking(seat: 3, name: 'Jean', cash: price),
    Booking(seat: 7, name: 'Grace', cash: price),
  ];
  final batch = FirebaseFirestore.instance.batch();
  for (final b in samples) {
    batch.set(myBookings().doc('${b.seat}'), b.toMap());
  }
  await batch.commit();
}
