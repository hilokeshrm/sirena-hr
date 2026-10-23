import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key});

  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  Key _key = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Policies')),
      body: Fetch<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => asList(await Api.instance.get('/policies')),
        builder: (context, list, reload) {
          final todo = list.where((p) => p['needsAck'] == true).toList();
          final rest = list.where((p) => p['needsAck'] != true).toList();
          Widget tile(Map<String, dynamic> p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () async {
                    await context.push('/policies/${p['id']}');
                    if (mounted) setState(() => _key = UniqueKey());
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: p['needsAck'] == true ? C.red : C.grey, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.article_outlined, size: 20, color: p['needsAck'] == true ? Colors.white : C.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${p['category']} · v${p['version']}'
                          '${p['ackedAt'] != null ? ' · read ${shortDay(p['ackedAt'] as String)}' : ''}'
                          '${p['needsAck'] == true && p['ackDueAt'] != null ? ' · due ${shortDay(p['ackDueAt'] as String)}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ]),
                    ),
                    if (p['needsAck'] == true) const StatusChip('PENDING_HR', label: 'To read') else const Icon(Icons.check, size: 20),
                  ]),
                ),
              );
          return PageBody(onRefresh: reload, children: [
            if (list.isEmpty) const EmptyView('No policies published yet.'),
            if (todo.isNotEmpty) ...[SectionTitle('Needs your OK (${todo.length})'), for (final p in todo) tile(p), gap8],
            if (rest.isNotEmpty) ...[const SectionTitle('All policies'), for (final p in rest) tile(p)],
          ]);
        },
      ),
    );
  }
}
