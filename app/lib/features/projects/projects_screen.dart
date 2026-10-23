import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  Key _key = UniqueKey();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final r = await Future.wait<dynamic>([Api.instance.get('/projects'), Api.instance.get('/tasks/mine')]);
    return (asList(r[0]), asList(r[1]));
  }

  Future<void> _create() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final client = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New project'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, decoration: inputDeco('Code, e.g. ATL-26')),
          gap12,
          TextField(controller: name, decoration: inputDeco('Name')),
          gap12,
          TextField(controller: client, decoration: inputDeco('Client (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await attempt(
      context,
      () => Api.instance.post('/projects', {'code': code.text.trim(), 'name': name.text.trim(), if (client.text.trim().isNotEmpty) 'client': client.text.trim()}),
      success: 'Project created',
    );
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final admin = Session.instance.can('admin') || Session.instance.me?['role'] == 'HR_ADMIN';
    return Scaffold(
      appBar: AppBar(title: const Text('Projects'), actions: [
        if (admin) Padding(padding: const EdgeInsets.only(right: 12), child: TextButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New'))),
      ]),
      body: Fetch<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        key: _key,
        load: _load,
        builder: (context, data, reload) {
          final (projects, tasks) = data;
          return PageBody(onRefresh: reload, children: [
            if (projects.isEmpty) const EmptyView("You're not on any project yet."),
            for (final p in projects)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () => context.push('/projects/${p['id']}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${p['code']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1))),
                      StatusChip(p['status'] as String),
                    ]),
                    const SizedBox(height: 6),
                    Text('${p['name']}', style: display(20)),
                    Text([
                      if (p['client'] != null) p['client'],
                      if (p['lead'] != null) 'Lead: ${(p['lead'] as Map)['fullName']}',
                      if (p['myRole'] != null) 'You: ${_role(p['myRole'] as String)}',
                    ].join(' · '), style: const TextStyle(fontSize: 13)),
                    gap12,
                    _Progress(done: p['tasksDone'] as int, total: (p['_count'] as Map)['tasks'] as int),
                  ]),
                ),
              ),
            gap8,
            SectionTitle('My open tasks', trailing: Text('${tasks.length}', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (tasks.isEmpty) const EmptyView('No open tasks. Nice.'),
            for (final t in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => context.push('/projects/${(t['project'] as Map)['id']}'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${(t['project'] as Map)['name']}${t['dueDate'] != null ? ' · due ${shortDay(t['dueDate'] as String)}' : ''}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    StatusChip(t['status'] as String),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

String _role(String r) => switch (r) { 'LEAD' => 'Lead', 'TECH_LEAD' => 'Tech lead', _ => 'Member' };

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8, color: C.red, backgroundColor: C.grey),
          ),
        ),
        const SizedBox(width: 10),
        Text('$done/$total tasks', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}
