import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  List<Map<String, dynamic>>? _days;
  String? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final days = asList(await Api.instance.get('/meals', {'from': ymd(now), 'to': ymd(now.add(const Duration(days: 9)))}));
      if (!mounted) return;
      setState(() {
        _days = days;
        _selected ??= days.isNotEmpty ? days.first['date'] as String : null;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _book(String date, String choice) async {
    await attempt(context, () => Api.instance.put('/meals/$date', {'choice': choice}),
        success: choice == 'NONE' ? 'No lunch that day' : 'Lunch booked');
    await _load();
  }

  Future<void> _plan(String date, String mode) async {
    await attempt(context, () => Api.instance.put('/plans/$date', {'mode': mode}));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lunch')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _days == null
              ? const Center(child: CircularProgressIndicator(color: C.red))
              : _days!.isEmpty
                  ? const EmptyView('No working days coming up.')
                  : _body(),
    );
  }

  Widget _body() {
    final d = _days!.firstWhere((x) => x['date'] == _selected, orElse: () => _days!.first);
    final booking = d['booking'] as Map?;
    final choice = booking?['choice'] as String?;
    final menu = d['menu'] as Map?;
    final isToday = d['date'] == todayYmd();
    final locked = isToday && d['canBook'] != true && booking != null;
    return PageBody(onRefresh: _load, maxWidth: 640, children: [
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _days!.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final x = _days![i];
            final on = x['date'] == d['date'];
            final c = (x['booking'] as Map?)?['choice'];
            final tag = x['holiday'] != null
                ? 'Holiday'
                : x['onLeave'] == true
                    ? 'Leave'
                    : x['mode'] == 'WFH'
                        ? 'WFH'
                        : c == 'VEG'
                            ? 'Veg'
                            : c == 'NON_VEG'
                                ? 'Non-veg'
                                : c == 'NONE'
                                    ? 'None'
                                    : 'Book';
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _selected = x['date'] as String),
              child: Container(
                width: 66,
                decoration: BoxDecoration(color: on ? C.ink : C.grey, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(DateFormat('EEE').format(day(x['date'] as String)), style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
                  Text(DateFormat('d').format(day(x['date'] as String)), style: display(20, color: on ? Colors.white : C.ink)),
                  Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: on ? Colors.white : (tag == 'Book' ? C.red : C.ink))),
                ]),
              ),
            );
          },
        ),
      ),
      gap16,
      Text(niceDay(d['date'] as String), style: display(22)),
      gap12,
      if (d['holiday'] != null)
        Panel(child: Text('${d['holiday']} — the office is closed.'))
      else if (d['onLeave'] == true)
        const Panel(child: Text("You're on leave. Your lunch was cancelled automatically."))
      else ...[
        if (!isToday || booking == null)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'OFFICE', label: Text('In office'), icon: Icon(Icons.apartment)),
              ButtonSegment(value: 'WFH', label: Text('From home'), icon: Icon(Icons.home_outlined)),
            ],
            selected: {d['mode'] as String},
            onSelectionChanged: (v) => _plan(d['date'] as String, v.first),
          ),
        gap12,
        if (booking != null && (choice == 'VEG' || choice == 'NON_VEG') && (locked || isToday))
          Panel(
            color: C.ink,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(locked ? "TODAY'S MEAL PASS · LOCKED" : "TODAY'S MEAL PASS", style: const TextStyle(color: C.grey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
              gap12,
              Row(children: [FoodMark(veg: choice == 'VEG', size: 26), const SizedBox(width: 10), Text(choice == 'VEG' ? 'Veg' : 'Non-veg', style: display(28, color: Colors.white))]),
              gap12,
              Text('${booking['passCode']}', style: display(44, color: Colors.white)),
              const Text('Show this at the counter', style: TextStyle(color: C.grey)),
            ]),
          ),
        if (d['mode'] == 'WFH')
          const Panel(child: Text("You're working from home this day, so lunch can't be booked. Switch to In office to book."))
        else if (d['canBook'] == true) ...[
          const Text('Pick your lunch', style: TextStyle(fontWeight: FontWeight.w800)),
          gap8,
          _Option(veg: true, selected: choice == 'VEG', menu: menu?['veg'] as String?, onTap: () => _book(d['date'] as String, 'VEG')),
          gap8,
          _Option(veg: false, selected: choice == 'NON_VEG', menu: menu?['nonVeg'] as String?, onTap: () => _book(d['date'] as String, 'NON_VEG')),
          gap8,
          TextButton(onPressed: () => _book(d['date'] as String, 'NONE'), child: Text(choice == 'NONE' ? 'Skipping lunch this day' : 'Skip lunch this day')),
        ] else if (booking == null)
          Panel(child: Text('${d['reason'] ?? 'Booking is closed'}.')),
      ],
      gap16,
      const Text('Book by the cut-off time each day. If your leave is approved, that day’s lunch is cancelled automatically.', style: TextStyle(fontSize: 13)),
    ]);
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.veg, required this.selected, required this.onTap, this.menu});
  final bool veg;
  final bool selected;
  final String? menu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? (veg ? C.veg : C.nonVeg) : C.grey, width: selected ? 3 : 1.5),
            ),
            child: Row(children: [
              FoodMark(veg: veg, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(veg ? 'Veg' : 'Non-veg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (menu != null) Text(menu!, style: const TextStyle(fontSize: 13)),
                ]),
              ),
              if (selected) Icon(Icons.check_circle, color: veg ? C.veg : C.nonVeg),
            ]),
          ),
        ),
      );
}
