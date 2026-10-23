import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  Key _key = UniqueKey();

  Future<void> _decide(String id, bool approve) async {
    final comment = await askText(context, title: approve ? 'Approve request' : 'Decline request', label: 'Comment (optional)', action: approve ? 'Approve' : 'Decline');
    if (comment == null || !mounted) return;
    await attempt(context, () => Api.instance.post('/leave/requests/$id/${approve ? 'approve' : 'reject'}', {if (comment.isNotEmpty) 'comment': comment}),
        success: approve ? 'Approved' : 'Declined');
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave approvals')),
      body: Fetch<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => asList(await Api.instance.get('/leave/requests', {'scope': 'approvals'})),
        builder: (context, list, reload) => PageBody(onRefresh: reload, children: [
          if (list.isEmpty) const EmptyView('Nothing waiting for you.'),
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                onTap: () => context.push('/leave/requests/${r['id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Avatar((r['employee'] as Map)['fullName'] as String),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(r['employee'] as Map)['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${(r['employee'] as Map)['designation'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    StatusChip(r['status'] as String),
                  ]),
                  gap12,
                  Text('${(r['leaveType'] as Map)['name']} · ${dayRange(r['fromDate'] as String, r['toDate'] as String)} · ${num1(r['days'])} day${r['days'] == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (r['reason'] != null) Text('“${r['reason']}”'),
                  gap12,
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => _decide(r['id'] as String, false), child: const Text('Decline'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(onPressed: () => _decide(r['id'] as String, true), child: const Text('Approve'))),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
