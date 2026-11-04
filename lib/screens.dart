import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'bus.dart';
import 'weather.dart';

const String noInternet = 'Could not save. Check your internet connection.';

// ---------------- 1. SEAT MAP ----------------

class SeatMapScreen extends StatefulWidget {
  const SeatMapScreen({super.key});

  @override
  State<SeatMapScreen> createState() => _SeatMapScreenState();
}

class _SeatMapScreenState extends State<SeatMapScreen> {
  // Live bookings: the list now, and again every time it changes.
  final bookings = myBookings().snapshots();

  void open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Booking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => open(const WaitlistScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Route: $route  -  $price RWF',
                style: TextStyle(fontSize: 20)),
            const HuyeWeather(),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: bookings,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load the bookings.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  Bus bus = Bus(snapshot.data!.docs.map(Booking.fromDoc).toList());
                  return seatMap(bus);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget seatMap(Bus bus) {
    return Column(
      children: [
        Text('Seats sold: ${bus.seatsSold}'),
        Text('Money made: ${bus.moneyMade} RWF'),
        if (bus.seatsSold == 0) const Text('No bookings yet. Tap a seat to book.'),
        const SizedBox(height: 16),

        // The 12 seats, 4 per row.
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: List.generate(seatCount, (i) {
              String? name = bus.seats[i];
              bool free = name == null;

              return GestureDetector(
                onTap: () {
                  if (free) {
                    open(BookSeatScreen(seat: i));
                  } else {
                    open(BookingDetailsScreen(seat: i, name: name));
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: free ? Colors.green[100] : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    free ? 'Seat ${i + 1}\nFree' : 'Seat ${i + 1}\n$name',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }),
          ),
        ),

        // Only when the bus is full.
        if (bus.isFull)
          ElevatedButton(
            onPressed: () => open(const WaitlistScreen()),
            child: const Text('Bus is full - Join waitlist'),
          ),
      ],
    );
  }
}

// Today's weather in Huye, shown on the seat map.
// It has 3 states: loading, error, data.
class HuyeWeather extends StatefulWidget {
  const HuyeWeather({super.key});

  @override
  State<HuyeWeather> createState() => _HuyeWeatherState();
}

class _HuyeWeatherState extends State<HuyeWeather> {
  Weather? weather;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await fetchWeather();
      if (!mounted) return;
      setState(() {
        weather = result;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load the weather';
      });
    }
  }

  void retry() {
    setState(() {
      loading = true;
      error = null;
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // 2. Error
    if (error != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 18),
          const SizedBox(width: 6),
          Text(error!),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      );
    }

    // 3. Data
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        'Weather in Huye: ${weather!.temperature.round()}°C, '
        '${describe(weather!.code)}',
      ),
    );
  }
}

// ---------------- 2. BOOK A SEAT ----------------

class BookSeatScreen extends StatefulWidget {
  final int seat;
  const BookSeatScreen({super.key, required this.seat});

  @override
  State<BookSeatScreen> createState() => _BookSeatScreenState();
}

class _BookSeatScreenState extends State<BookSeatScreen> {
  TextEditingController nameField = TextEditingController();
  TextEditingController cashField = TextEditingController();
  String message = '';
  bool busy = false;

  Future<void> bookSeat() async {
    int cash = int.tryParse(cashField.text) ?? 0;

    // Check the cash first.
    Map<int, int>? notes = change(cash);
    if (notes == null) {
      setState(() {
        message = 'Cash must be at least $price RWF and a multiple of 100';
      });
      return;
    }

    // Then try to book.
    setState(() {
      busy = true;
      message = '';
    });
    String? error;
    try {
      error = await book(widget.seat, nameField.text, cash);
    } on FirebaseException {
      error = noInternet;
    }
    if (!mounted) return;
    setState(() {
      busy = false;
    });
    if (error != null) {
      setState(() {
        message = error!;
      });
      return;
    }

    // Worked: show the change, e.g. "5000 x 1 · 2000 x 1".
    String changeText = notes.isEmpty
        ? 'No change'
        : notes.entries.map((e) => '${e.key} x ${e.value}').join(' · ');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Booked!'),
        content: Text('Change: $changeText'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // close dialog
              Navigator.pop(context); // back to seat map
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book seat ${widget.seat + 1}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameField,
              decoration: const InputDecoration(labelText: 'Passenger name'),
            ),
            TextField(
              controller: cashField,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cash given (RWF)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: busy ? null : bookSeat,
              child: const Text('Book'),
            ),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 3. BOOKING DETAILS ----------------

class BookingDetailsScreen extends StatefulWidget {
  final int seat;
  final String name;
  const BookingDetailsScreen(
      {super.key, required this.seat, required this.name});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  String message = '';

  Future<void> cancelBooking() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This booking will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      String? moved = await cancel(widget.seat);
      if (!mounted) return;
      ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context); // back to seat map
      if (moved != null) {
        messenger.showSnackBar(SnackBar(content: Text(moved)));
      }
    } on FirebaseException {
      if (!mounted) return;
      setState(() {
        message = noInternet;
      });
    }
  }

  Future<void> editName() async {
    TextEditingController nameField = TextEditingController(text: widget.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(controller: nameField),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, nameField.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;

    String? error;
    try {
      error = await rename(widget.seat, newName);
    } on FirebaseException {
      error = noInternet;
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        message = error!;
      });
      return;
    }
    Navigator.pop(context); // back to seat map
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Seat ${widget.seat + 1}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Passenger: ${widget.name}',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: editName,
              child: const Text('Edit name'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: cancelBooking,
              child: const Text('Cancel booking'),
            ),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 4. WAITLIST ----------------

class WaitlistScreen extends StatefulWidget {
  const WaitlistScreen({super.key});

  @override
  State<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends State<WaitlistScreen> {
  // Live data: the seats (to know if the bus is full) and the waitlist.
  final bookings = myBookings().snapshots();
  final waiting = myWaitlist().orderBy('joinedAt').snapshots();

  TextEditingController nameField = TextEditingController();
  bool priority = false;
  bool busy = false;
  String message = '';

  Future<void> join() async {
    setState(() {
      busy = true;
      message = '';
    });

    String? error;
    try {
      error = await joinWaitlist(nameField.text, priority);
    } on FirebaseException {
      error = noInternet;
    }
    if (!mounted) return;

    setState(() {
      busy = false;
      if (error != null) {
        message = error;
      } else {
        nameField.clear();
        priority = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waitlist')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Join form: only when the bus is full.
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: bookings,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.length < seatCount) {
                  return const SizedBox.shrink();
                }
                return joinForm();
              },
            ),

            // The list.
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: waiting,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load the waitlist.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  List<Waiting> people =
                      inOrder(snapshot.data!.docs.map(Waiting.fromDoc).toList());
                  if (people.isEmpty) {
                    return const Center(child: Text('Nobody is waiting'));
                  }

                  return ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, i) {
                      Waiting person = people[i];
                      return ListTile(
                        leading: Text('${i + 1}'),
                        title: Text(person.name),
                        trailing: person.priority
                            ? const Text('PRIORITY',
                                style: TextStyle(color: Colors.orange))
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget joinForm() {
    return Column(
      children: [
        TextField(
          controller: nameField,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        SwitchListTile(
          title: const Text('Priority (elderly, pregnant, disabled)'),
          value: priority,
          onChanged: (value) => setState(() => priority = value),
        ),
        ElevatedButton(
          onPressed: busy ? null : join,
          child: const Text('Join waitlist'),
        ),
        Text(message, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
      ],
    );
  }
}
