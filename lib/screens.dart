import 'package:flutter/material.dart';

import 'bus.dart';
import 'weather.dart';

// ---------------- 1. SEAT MAP ----------------

class SeatMapScreen extends StatefulWidget {
  final Bus bus;
  const SeatMapScreen({super.key, required this.bus});

  @override
  State<SeatMapScreen> createState() => _SeatMapScreenState();
}

class _SeatMapScreenState extends State<SeatMapScreen> {
  // Opens another screen, then refreshes this one when we come back.
  Future<void> open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Bus bus = widget.bus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Booking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => open(WaitlistScreen(bus: bus)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Route: ${bus.route}  -  ${bus.price} RWF',
                style: const TextStyle(fontSize: 20)),
            const HuyeWeather(),
            const SizedBox(height: 8),
            Text('Seats sold: ${bus.seatsSold}'),
            Text('Money made: ${bus.moneyMade} RWF'),
            const SizedBox(height: 16),

            // The 12 seats, 4 per row.
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: List.generate(12, (i) {
                  String? name = bus.seats[i];
                  bool free = name == null;

                  return GestureDetector(
                    onTap: () {
                      if (free) {
                        open(BookSeatScreen(bus: bus, seat: i));
                      } else {
                        open(BookingDetailsScreen(bus: bus, seat: i));
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
                onPressed: () => open(WaitlistScreen(bus: bus)),
                child: const Text('Bus is full - Join waitlist'),
              ),
          ],
        ),
      ),
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
      setState(() {
        weather = result;
        loading = false;
        error = null;
      });
    } catch (e) {
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
  final Bus bus;
  final int seat;
  const BookSeatScreen({super.key, required this.bus, required this.seat});

  @override
  State<BookSeatScreen> createState() => _BookSeatScreenState();
}

class _BookSeatScreenState extends State<BookSeatScreen> {
  TextEditingController nameField = TextEditingController();
  TextEditingController cashField = TextEditingController();
  String message = '';

  void bookSeat() {
    Bus bus = widget.bus;
    int cash = int.tryParse(cashField.text) ?? 0;

    // Check the cash first.
    Map<int, int>? change = bus.change(cash);
    if (change == null) {
      setState(() {
        message = 'Cash must be at least ${bus.price} RWF and a multiple of 100';
      });
      return;
    }

    // Then try to book.
    String? error = bus.book(widget.seat, nameField.text);
    if (error != null) {
      setState(() {
        message = error;
      });
      return;
    }

    // Worked: show the change, e.g. "5000 x 1 · 2000 x 1".
    String changeText = change.isEmpty
        ? 'No change'
        : change.entries.map((e) => '${e.key} x ${e.value}').join(' · ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booked!'),
        content: Text('Change: $changeText'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
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
            ElevatedButton(onPressed: bookSeat, child: const Text('Book')),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 3. BOOKING DETAILS ----------------

class BookingDetailsScreen extends StatelessWidget {
  final Bus bus;
  final int seat;
  const BookingDetailsScreen(
      {super.key, required this.bus, required this.seat});

  void cancelBooking(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This booking will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              String? moved = bus.cancel(seat);
              Navigator.pop(dialogContext); // close dialog
              Navigator.pop(context); // back to seat map
              if (moved != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(moved)));
              }
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Seat ${seat + 1}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Passenger: ${bus.seats[seat]}',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => cancelBooking(context),
              child: const Text('Cancel booking'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 4. WAITLIST ----------------

class WaitlistScreen extends StatefulWidget {
  final Bus bus;
  const WaitlistScreen({super.key, required this.bus});

  @override
  State<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends State<WaitlistScreen> {
  TextEditingController nameField = TextEditingController();
  bool priority = false;

  void join() {
    if (nameField.text.trim().isEmpty) return;
    setState(() {
      widget.bus.joinWaitlist(nameField.text, priority);
      nameField.clear();
      priority = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Bus bus = widget.bus;

    return Scaffold(
      appBar: AppBar(title: const Text('Waitlist')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Join form: only when the bus is full.
            if (bus.isFull) ...[
              TextField(
                controller: nameField,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              SwitchListTile(
                title: const Text('Priority (elderly, pregnant, disabled)'),
                value: priority,
                onChanged: (value) => setState(() => priority = value),
              ),
              ElevatedButton(onPressed: join, child: const Text('Join waitlist')),
              const SizedBox(height: 16),
            ],

            // The list.
            Expanded(
              child: bus.waitlist.isEmpty
                  ? const Center(child: Text('Nobody is waiting'))
                  : ListView.builder(
                      itemCount: bus.waitlist.length,
                      itemBuilder: (context, i) {
                        Waiting person = bus.waitlist[i];
                        return ListTile(
                          leading: Text('${i + 1}'),
                          title: Text(person.name),
                          trailing: person.priority
                              ? const Text('PRIORITY',
                                  style: TextStyle(color: Colors.orange))
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
