import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  String _filter = 'All';
  Key _key = UniqueKey();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final r = await Future.wait<dynamic>([Api.instance.get('/leave/balances'), Api.instance.get('/leave/requests', {'scope': 'mine'})]);
    return (asList(r[0]), asList(r[1]));
  }

  bool _matches(Map<String, dynamic> r) => switch (_filter) {
        'Pending' => (r['status'] as String).startsWith('PENDING'),
        'Approved' => r['status'] == 'APPROVED',
        'Declined' => r['status'] == 'REJECTED' || r['status'] == 'CANCELLED',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My leave'), actions: [
        if (Session.instance.can('approveLeave'))
          TextButton(onPressed: () => context.push('/leave/approvals'), child: const Text('Approvals')),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () async {
              await context.push('/leave/apply');
              if (mounted) setState(() => _key = UniqueKey());
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Apply'),
          ),
        ),
      ]),
      body: Fetch<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        key: _key,
        load: _load,
        builder: (context, data, reload) {
          final (balances, requests) = data;
          final shown = balances.where((b) => b['unlimited'] != true && ((b['balance'] as num) != 0 || (b['pending'] as num) != 0)).toList();
          final list = requests.where(_matches).toList();
          return PageBody(onRefresh: reload, children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final b in shown)
                  Panel(
                    color: b['code'] == 'CL' ? C.ink : C.grey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(num1(b['available']), style: display(28, color: b['code'] == 'CL' ? Colors.white : C.ink)),
                      Text(
                        '${b['name']}${b['yearlyQuota'] != null ? ' · of ${num1(b['yearlyQuota'])}' : ''}${(b['pending'] as num) > 0 ? ' · ${num1(b['pending'])} pending' : ''}',
                        style: TextStyle(fontSize: 12, color: b['code'] == 'CL' ? Colors.white : C.ink),
                        maxLines: 2,
                      ),
                    ]),
                  ),
              ],
            ),
            gap16,
            Wrap(spacing: 8, children: [
              for (final f in ['All', 'Pending', 'Approved', 'Declined'])
                ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f), showCheckmark: false),
            ]),
            gap12,
            if (list.isEmpty) const EmptyView('No leave requests here.'),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () async {
                    await context.push('/leave/requests/${r['id']}');
                    reload();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(r['leaveType'] as Map)['name']} · ${num1(r['days'])} day${r['days'] == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(dayRange(r['fromDate'] as String, r['toDate'] as String), style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                    StatusChip(r['status'] as String),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
