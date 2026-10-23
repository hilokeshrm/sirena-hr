import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _taskStatuses = ['TODO', 'IN_PROGRESS', 'IN_REVIEW', 'DONE'];

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.id});
  final String id;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  Key _key = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Fetch<Map<String, dynamic>>(
      key: _key,
      load: () async => asMap(await Api.instance.get('/projects/${widget.id}')),
      builder: (context, p, reload) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${p['name']}'),
            bottom: const TabBar(
              labelColor: C.ink,
              indicatorColor: C.red,
              tabs: [Tab(text: 'Tasks'), Tab(text: 'Files'), Tab(text: 'Team')],
            ),
          ),
          body: TabBarView(children: [
            _TasksTab(project: p),
            _FilesTab(projectId: widget.id),
            _TeamTab(project: p, onChanged: () => setState(() => _key = UniqueKey())),
          ]),
        ),
      ),
    );
  }
}

// ── Tasks ──

class _TasksTab extends StatefulWidget {
  const _TasksTab({required this.project});
  final Map<String, dynamic> project;

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  Key _key = UniqueKey();
  bool _mine = false;

  String get _id => widget.project['id'] as String;
  List<Map<String, dynamic>> get _members => asList(widget.project['members']);

  void _reload() => setState(() => _key = UniqueKey());

  Future<void> _setStatus(Map<String, dynamic> t, String status) async {
    await attempt(context, () => Api.instance.patch('/tasks/${t['id']}', {'status': status}));
    _reload();
  }

  Future<void> _add() async {
    final title = TextEditingController();
    String priority = 'MEDIUM';
    String? assignee = Session.instance.id;
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New task'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: title, decoration: inputDeco('What needs doing?'), autofocus: true),
              gap12,
              DropdownButtonFormField<String?>(
                value: assignee,
                decoration: inputDeco('Assignee'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Unassigned')),
                  for (final m in _members)
                    DropdownMenuItem(value: (m['employee'] as Map)['id'] as String, child: Text('${(m['employee'] as Map)['fullName']}')),
                ],
                onChanged: (v) => set(() => assignee = v),
              ),
              gap12,
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'LOW', label: Text('Low')), ButtonSegment(value: 'MEDIUM', label: Text('Medium')), ButtonSegment(value: 'HIGH', label: Text('High'))],
                selected: {priority},
                onSelectionChanged: (v) => set(() => priority = v.first),
              ),
              gap12,
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(due == null ? 'Due date (optional)' : niceDay(ymd(due!))),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
                  if (d != null) set(() => due = d);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    await attempt(
      context,
      () => Api.instance.post('/projects/$_id/tasks', {
        'title': title.text.trim(),
        'priority': priority,
        if (assignee != null) 'assigneeId': assignee,
        if (due != null) 'dueDate': ymd(due!),
      }),
      success: 'Task added',
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final milestones = asList(widget.project['milestones']);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.red,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Task'),
      ),
      body: Fetch<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => asList(await Api.instance.get('/projects/$_id/tasks', {if (_mine) 'mine': 'true'})),
        builder: (context, tasks, reload) => PageBody(onRefresh: reload, children: [
          if (milestones.isNotEmpty) ...[
            const SectionTitle('Milestones'),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: milestones.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = milestones[i];
                  final done = m['done'] == true;
                  return Container(
                    width: 180,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: done ? C.ink : C.grey, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: done ? Colors.white : C.ink)),
                      Text(done ? 'Done' : (m['dueDate'] != null ? 'Due ${shortDay(m['dueDate'] as String)}' : 'No date'),
                          style: TextStyle(fontSize: 12, color: done ? Colors.white : C.ink)),
                    ]),
                  );
                },
              ),
            ),
            gap12,
          ],
          Row(children: [
            Expanded(child: SectionTitle('Tasks (${tasks.length})')),
            FilterChip(label: const Text('Only mine'), selected: _mine, showCheckmark: false, onSelected: (v) => setState(() => (_mine = v, _key = UniqueKey()))),
          ]),
          if (tasks.isEmpty) const EmptyView('No tasks yet.'),
          for (final status in _taskStatuses)
            if (tasks.any((t) => t['status'] == status)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(prettyEnum(status).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              for (final t in tasks.where((t) => t['status'] == status))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                    child: Row(children: [
                      Checkbox(
                        value: t['status'] == 'DONE',
                        activeColor: C.ink,
                        onChanged: (v) => _setStatus(t, v == true ? 'DONE' : 'TODO'),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${t['title']}',
                              style: TextStyle(fontWeight: FontWeight.w700, decoration: t['status'] == 'DONE' ? TextDecoration.lineThrough : null)),
                          Text(
                            [
                              (t['assignee'] as Map?)?['fullName'] ?? 'Unassigned',
                              if (t['dueDate'] != null) 'due ${shortDay(t['dueDate'] as String)}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ]),
                      ),
                      if (t['priority'] == 'HIGH' || t['priority'] == 'URGENT') StatusChip(t['priority'] as String),
                      PopupMenuButton<String>(
                        tooltip: 'Move',
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (s) => _setStatus(t, s),
                        itemBuilder: (_) => [
                          for (final s in _taskStatuses)
                            if (s != t['status']) PopupMenuItem(value: s, child: Text('Move to ${prettyEnum(s).toLowerCase()}')),
                        ],
                      ),
                    ]),
                  ),
                ),
            ],
          const SizedBox(height: 72),
        ]),
      ),
    );
  }
}

// ── Files ──

class _FilesTab extends StatefulWidget {
  const _FilesTab({required this.projectId});
  final String projectId;

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  Key _key = UniqueKey();

  Future<void> _upload(Map<String, dynamic> folder) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final f = picked?.files.single;
    if (f == null || f.bytes == null || !mounted) return;
    showSnack(context, 'Uploading ${f.name}…');
    await attempt(context, () => Api.instance.upload('/folders/${folder['id']}/files', f.name, f.bytes!), success: 'Uploaded ${f.name}');
    if (mounted) setState(() => _key = UniqueKey());
  }

  Future<void> _open(Map<String, dynamic> file) async {
    final res = await attempt(context, () => Api.instance.post('/files/${file['id']}/link'));
    if (res == null) return;
    final url = Uri.parse('${AppConfig.origin}${asMap(res)['path']}');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) showSnack(context, "Couldn't open the file");
  }

  static String _size(int b) => b < 1024 * 1024 ? '${(b / 1024).ceil()} KB' : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  static IconData _icon(String mime) {
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('sheet') || mime.contains('excel') || mime.contains('csv')) return Icons.table_chart_outlined;
    if (mime.contains('zip')) return Icons.folder_zip_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Fetch<List<Map<String, dynamic>>>(
      key: _key,
      load: () async => asList(await Api.instance.get('/projects/${widget.projectId}/folders')),
      builder: (context, folders, reload) => PageBody(onRefresh: reload, children: [
        if (folders.isEmpty) const EmptyView('No folders you can see.'),
        for (final folder in folders) ...[
          SectionTitle(
            '${folder['name']}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (folder['sensitivity'] == 'RESTRICTED')
                const Padding(padding: EdgeInsets.only(right: 4), child: StatusChip('RESTRICTED', label: 'Restricted')),
              TextButton.icon(onPressed: () => _upload(folder), icon: const Icon(Icons.upload, size: 18), label: const Text('Upload')),
            ]),
          ),
          if (asList(folder['files']).isEmpty) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Empty folder')),
          for (final f in asList(folder['files']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                onTap: () => _open(f),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(12)),
                    child: Icon(_icon(f['mime'] as String), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('v${f['version']} · ${_size(f['size'] as int)} · ${(f['uploadedBy'] as Map)['fullName']} · ${shortDay(f['createdAt'] as String)}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.download, size: 20),
                ]),
              ),
            ),
          gap8,
        ],
      ]),
    );
  }
}

// ── Team ──

class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.project, required this.onChanged});
  final Map<String, dynamic> project;
  final VoidCallback onChanged;

  Future<void> _addMember(BuildContext context) async {
    final people = asList(await Api.instance.get('/employees'));
    if (!context.mounted) return;
    final existing = asList(project['members']).map((m) => (m['employee'] as Map)['id']).toSet();
    String? who;
    String role = 'MEMBER';
    final alloc = TextEditingController(text: '100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add to team'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                value: who,
                isExpanded: true,
                decoration: inputDeco('Person'),
                items: [
                  for (final e in people.where((e) => !existing.contains(e['id'])))
                    DropdownMenuItem(value: e['id'] as String, child: Text('${e['fullName']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => who = v),
              ),
              gap12,
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'MEMBER', label: Text('Member')), ButtonSegment(value: 'TECH_LEAD', label: Text('Tech lead')), ButtonSegment(value: 'LEAD', label: Text('Lead'))],
                selected: {role},
                onSelectionChanged: (v) => set(() => role = v.first),
              ),
              gap12,
              TextField(controller: alloc, decoration: inputDeco('Allocation %'), keyboardType: TextInputType.number),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || who == null || !context.mounted) return;
    await attempt(
      context,
      () => Api.instance.post('/projects/${project['id']}/members', {'employeeId': who, 'role': role, 'allocation': int.tryParse(alloc.text) ?? 100}),
      success: 'Added to the team',
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final members = asList(project['members']);
    final canEdit = project['canEdit'] == true || Session.instance.can('admin');
    return PageBody(children: [
      Panel(
        color: C.grey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('${project['code']}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))), StatusChip(project['status'] as String)]),
          gap8,
          if (project['client'] != null) Text('Client: ${project['client']}'),
          if (project['startDate'] != null)
            Text('${shortDay(project['startDate'] as String)}${project['endDate'] != null ? ' – ${shortDay(project['endDate'] as String)}' : ''}'),
        ]),
      ),
      gap8,
      SectionTitle('Team (${members.length})',
          trailing: canEdit ? TextButton.icon(onPressed: () => _addMember(context), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add')) : null),
      for (final m in members)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Avatar((m['employee'] as Map)['fullName'] as String, size: 36, dark: m['role'] == 'LEAD'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(m['employee'] as Map)['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${(m['employee'] as Map)['designation'] ?? ''}', style: const TextStyle(fontSize: 12)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_role(m['role'] as String), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${m['allocation']}%', style: const TextStyle(fontSize: 12)),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

String _role(String r) => switch (r) { 'LEAD' => 'Lead', 'TECH_LEAD' => 'Tech lead', _ => 'Member' };
