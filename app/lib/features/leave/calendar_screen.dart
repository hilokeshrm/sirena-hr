import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Who's off this month: team leave and holidays.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _selected = todayYmd();

  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  void _shift(int n) => setState(() {
        _month = DateTime(_month.year, _month.month + n);
        _selected = ymd(_month);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Who's off")),
      body: Fetch<Map<String, dynamic>>(
        key: ValueKey(_monthKey),
        load: () async => asMap(await Api.instance.get('/leave/calendar', {'month': _monthKey})),
        builder: (context, data, reload) {
          final leaves = asList(data['leaves']);
          final holidays = asList(data['holidays']);
          bool off(String d) => leaves.any((l) => (l['fromDate'] as String).compareTo(d) <= 0 && (l['toDate'] as String).compareTo(d) >= 0);
          Map<String, dynamic>? holiday(String d) => holidays.where((h) => h['date'] == d).firstOrNull;
          final first = DateTime(_month.year, _month.month, 1);
          final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
          final lead = first.weekday - 1; // Monday first
          final people = leaves.where((l) => (l['fromDate'] as String).compareTo(_selected) <= 0 && (l['toDate'] as String).compareTo(_selected) >= 0).toList();
          final h = holiday(_selected);
          return PageBody(maxWidth: 560, onRefresh: reload, children: [
            Row(children: [
              IconButton(tooltip: 'Previous month', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text(DateFormat('MMMM yyyy').format(_month), textAlign: TextAlign.center, style: display(20))),
              IconButton(tooltip: 'Next month', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ]),
            gap8,
            Row(children: [for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))))]),
            gap8,
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                for (var n = 1; n <= daysInMonth; n++)
                  Builder(builder: (context) {
                    final d = ymd(DateTime(_month.year, _month.month, n));
                    final sel = d == _selected;
                    final isToday = d == todayYmd();
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selected = d),
                      child: Container(
                        decoration: BoxDecoration(color: sel ? C.ink : (isToday ? C.grey : Colors.transparent), borderRadius: BorderRadius.circular(12)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('$n',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : (holiday(d) != null ? C.red : C.ink),
                                decoration: holiday(d) != null ? TextDecoration.underline : null,
                              )),
                          const SizedBox(height: 3),
                          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: off(d) ? C.red : Colors.transparent)),
                        ]),
                      ),
                    );
                  }),
              ],
            ),
            gap8,
            const Text('Red dot: someone is off · red date: holiday', style: TextStyle(fontSize: 12)),
            gap16,
            SectionTitle(niceDay(_selected)),
            if (h != null) Panel(color: C.ink, child: Text('${h['name']}${h['optional'] == true ? ' (optional holiday)' : ' · office closed'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            if (h != null) gap8,
            if (people.isEmpty && h == null) const EmptyView('Everyone is in.'),
            for (final l in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Avatar((l['employee'] as Map)['fullName'] as String, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(l['employee'] as Map)['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${l['type']} · ${dayRange(l['fromDate'] as String, l['toDate'] as String)}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    StatusChip(l['approved'] == true ? 'APPROVED' : 'PENDING_MANAGER', label: l['approved'] == true ? 'Approved' : 'Pending'),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
