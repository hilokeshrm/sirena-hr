import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// HR: who checked in on a day, how, and which check-ins need a look.
class AttendanceAdmin extends StatefulWidget {
  const AttendanceAdmin({super.key});

  @override
  State<AttendanceAdmin> createState() => _AttendanceAdminState();
}

class _AttendanceAdminState extends State<AttendanceAdmin> {
  DateTime _date = DateTime.now();
  bool _flaggedOnly = false;

  @override
  Widget build(BuildContext context) {
    final d = ymd(_date);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance'), actions: [
        TextButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(niceDay(d)),
          onPressed: () async {
            final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime.now());
            if (p != null) setState(() => _date = p);
          },
        ),
      ]),
      body: Fetch<Map<String, dynamic>>(
        key: ValueKey(d),
        load: () async => asMap(await Api.instance.get('/attendance/day', {'date': d})),
        builder: (context, data, reload) {
          final s = asMap(data['summary']);
          final rows = asList(data['rows']).where((r) => !_flaggedOnly || r['flagged'] == true).toList();
          return PageBody(onRefresh: reload, children: [
            Row(children: [
              for (final (label, value, dark) in [
                ('Checked in', s['checkedIn'], true),
                ('Office', s['office'], false),
                ('WFH', s['wfh'], false),
                ('Flagged', s['flagged'], false),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Panel(
                      color: dark ? C.ink : C.grey,
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$value', style: display(26, color: dark ? Colors.white : (label == 'Flagged' && value != 0 ? C.red : C.ink))),
                        Text(label, style: TextStyle(fontSize: 12, color: dark ? Colors.white : C.ink)),
                      ]),
                    ),
                  ),
                ),
            ]),
            gap12,
            Row(children: [
              const Expanded(child: Text('Flagged = manual "office" check-in from outside the office network.', style: TextStyle(fontSize: 12))),
              FilterChip(label: const Text('Flagged only'), selected: _flaggedOnly, showCheckmark: false, onSelected: (v) => setState(() => _flaggedOnly = v)),
            ]),
            gap12,
            if (rows.isEmpty) const EmptyView('No check-ins.'),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Avatar((r['employee'] as Map)['fullName'] as String, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(r['employee'] as Map)['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${r['mode'] == 'OFFICE' ? 'Office' : 'WFH'} · ${r['method'] == 'WIFI' ? 'Wi-Fi' : r['method'] == 'GPS' ? 'Location' : 'Manual'}'
                          '${r['ip'] != null ? ' · ${r['ip']}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(
                        '${r['checkInAt'] != null ? clock(r['checkInAt'] as String) : '—'} – ${r['checkOutAt'] != null ? clock(r['checkOutAt'] as String) : '…'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (r['flagged'] == true) const Text('Flagged', style: TextStyle(color: C.red, fontSize: 12, fontWeight: FontWeight.w800)),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
