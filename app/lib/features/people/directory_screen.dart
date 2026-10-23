import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const todayLabel = {'OFFICE': 'In office', 'WFH': 'WFH', 'ON_LEAVE': 'On leave', 'NOT_IN': 'Not in yet'};

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  String _q = '';
  String _where = 'All';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(children: [
                TextField(
                  decoration: inputDeco('Search name, role or code').copyWith(prefixIcon: const Icon(Icons.search)),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v.trim()));
                  },
                ),
                gap8,
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in ['All', 'OFFICE', 'WFH', 'ON_LEAVE'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Text(f == 'All' ? 'Everyone' : todayLabel[f]!),
                          selected: _where == f,
                          onSelected: (_) => setState(() => _where = f),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Fetch<List<Map<String, dynamic>>>(
            key: ValueKey(_q),
            load: () async => asList(await Api.instance.get('/employees', {if (_q.isNotEmpty) 'q': _q})),
            builder: (context, people, reload) {
              final shown = _where == 'All' ? people : people.where((p) => p['today'] == _where).toList();
              return PageBody(onRefresh: reload, children: [
                if (shown.isEmpty) const EmptyView('Nobody matches.'),
                for (final p in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      onTap: () => context.push('/people/${p['id']}'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Avatar(p['fullName'] as String),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              [p['designation'], (p['department'] as Map?)?['name'], (p['location'] as Map?)?['name']].whereType<String>().join(' · '),
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        _TodayDot(p['today'] as String),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _TodayDot extends StatelessWidget {
  const _TodayDot(this.today);
  final String today;

  @override
  Widget build(BuildContext context) {
    final color = switch (today) { 'OFFICE' => C.ink, 'ON_LEAVE' => C.red, _ => C.grey };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: C.ink.withValues(alpha: .2)))),
      const SizedBox(width: 6),
      Text(todayLabel[today] ?? today, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}
