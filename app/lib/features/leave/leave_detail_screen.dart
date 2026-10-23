import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class LeaveDetailScreen extends StatefulWidget {
  const LeaveDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<LeaveDetailScreen> createState() => _LeaveDetailScreenState();
}

class _LeaveDetailScreenState extends State<LeaveDetailScreen> {
  Key _key = UniqueKey();

  Future<void> _act(String action, {bool askComment = false}) async {
    String? comment;
    if (askComment) {
      comment = await askText(context, title: action == 'reject' ? 'Decline request' : 'Approve request', label: 'Comment (optional)', action: action == 'reject' ? 'Decline' : 'Approve');
      if (comment == null) return;
    }
    if (!mounted) return;
    await attempt(context, () => Api.instance.post('/leave/requests/${widget.id}/$action', {if (comment != null && comment.isNotEmpty) 'comment': comment}));
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave request')),
      body: Fetch<Map<String, dynamic>>(
        key: _key,
        load: () async => asMap(await Api.instance.get('/leave/requests/${widget.id}')),
        builder: (context, r, reload) {
          final mine = (r['employee'] as Map)['id'] == Session.instance.id;
          final status = r['status'] as String;
          final approvals = asList(r['approvals']);
          final canCancel = mine && (status.startsWith('PENDING') || (status == 'APPROVED' && (r['fromDate'] as String).compareTo(todayYmd()) > 0));
          return PageBody(maxWidth: 600, onRefresh: reload, children: [
            Panel(
              color: C.grey,
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(((r['leaveType'] as Map)['name'] as String).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12))),
                  StatusChip(status),
                ]),
                gap12,
                Text(dayRange(r['fromDate'] as String, r['toDate'] as String), style: display(32)),
                Text('${num1(r['days'])} day${r['days'] == 1 ? '' : 's'}${r['halfDay'] != 'NONE' ? ' (${r['halfDay'] == 'FIRST' ? 'first' : 'second'} half)' : ''}'),
                if (!mine) ...[gap8, Text('${(r['employee'] as Map)['fullName']} · ${(r['employee'] as Map)['designation'] ?? ''}')],
                if (r['reason'] != null) ...[gap8, Text('“${r['reason']}”')],
              ]),
            ),
            gap16,
            const SectionTitle('Where it’s at'),
            _Step(done: true, title: 'Sent', sub: 'by ${(r['employee'] as Map)['fullName']}'),
            for (final a in approvals)
              _Step(
                done: a['approved'] == true,
                declined: a['approved'] != true,
                title: '${a['step'] == 'MANAGER' ? 'Manager' : 'HR'} ${a['approved'] == true ? 'approved' : 'declined'}',
                sub: '${(a['approver'] as Map)['fullName']}${a['comment'] != null ? ' · “${a['comment']}”' : ''}',
              ),
            if (status == 'PENDING_MANAGER')
              _Step(title: 'Waiting on manager', sub: '${(r['employee'] as Map)['manager']?['fullName'] ?? ''}', current: true),
            if (status == 'PENDING_HR') const _Step(title: 'Waiting on HR', sub: 'HR sign-off', current: true),
            const SizedBox(height: 24),
            if (r['canApprove'] == true)
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _act('reject', askComment: true), child: const Text('Decline'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => _act('approve', askComment: true), child: const Text('Approve'))),
              ]),
            if (canCancel)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: C.red),
                onPressed: () => _act('cancel'),
                child: const Text('Cancel request'),
              ),
          ]);
        },
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.sub, this.done = false, this.declined = false, this.current = false});
  final String title;
  final String sub;
  final bool done;
  final bool declined;
  final bool current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done ? C.ink : (declined ? C.red : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: current ? C.red : (done || declined ? Colors.transparent : C.grey), width: 2),
            ),
            child: Icon(declined ? Icons.close : Icons.check, size: 16, color: done || declined ? Colors.white : Colors.transparent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: current ? C.red : C.ink)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ]),
      );
}
