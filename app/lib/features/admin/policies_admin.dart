import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// HR: write policies, publish versions, and chase acknowledgements.
class PoliciesAdmin extends StatefulWidget {
  const PoliciesAdmin({super.key});

  @override
  State<PoliciesAdmin> createState() => _PoliciesAdminState();
}

class _PoliciesAdminState extends State<PoliciesAdmin> {
  Key _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  /// New policy (p == null) or a new version of an existing one.
  Future<void> _write([Map<String, dynamic>? p]) async {
    final title = TextEditingController();
    final category = TextEditingController(text: 'General');
    final body = TextEditingController();
    final summary = TextEditingController();
    bool requireAck = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(p == null ? 'New policy' : 'New version of ${p['title']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (p == null) ...[
                  TextField(controller: title, decoration: inputDeco('Title')),
                  gap12,
                  TextField(controller: category, decoration: inputDeco('Category, e.g. Leave, Conduct, IT')),
                  gap12,
                ],
                TextField(controller: body, decoration: inputDeco('Policy text'), minLines: 8, maxLines: 16),
                gap12,
                TextField(controller: summary, decoration: inputDeco(p == null ? 'Note (optional)' : 'What changed?')),
                if (p == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: C.red,
                    value: requireAck,
                    title: const Text('People must acknowledge it'),
                    onChanged: (v) => set(() => requireAck = v),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save as draft')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final s = summary.text.trim();
    await attempt(
      context,
      () => p == null
          ? Api.instance.post('/policies', {'title': title.text.trim(), 'category': category.text.trim(), 'body': body.text, 'requireAck': requireAck, if (s.isNotEmpty) 'changeSummary': s})
          : Api.instance.post('/policies/${p['id']}/versions', {'body': body.text, if (s.isNotEmpty) 'changeSummary': s}),
      success: 'Draft saved. Publish it when ready.',
    );
    _reload();
  }

  Future<void> _publish(Map<String, dynamic> p) async {
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Publish ${p['title']} v${p['version']}?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Everyone it applies to gets a notification.'),
            if (p['requireAck'] == true) ...[
              gap12,
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(due == null ? 'Acknowledge by (optional)' : 'Acknowledge by ${niceDay(ymd(due!))}'),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
                  if (d != null) set(() => due = d);
                },
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await attempt(context, () => Api.instance.post('/policy-versions/${p['versionId']}/publish', {if (due != null) 'ackDueAt': ymd(due!)}), success: 'Published');
    _reload();
  }

  Future<void> _acks(Map<String, dynamic> p) async {
    final data = await attempt(context, () => Api.instance.get('/policy-versions/${p['versionId']}/acks'));
    if (data == null || !mounted) return;
    final acked = asList(data['acked']);
    final pending = asList(data['pending']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p['title']} v${p['version']}'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView(children: [
            Text('Not yet (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800, color: C.red)),
            for (final e in pending) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${e['fullName']}')),
            gap16,
            Text('Acknowledged (${acked.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final e in acked) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${e['fullName']} · ${shortDay(e['at'] as String)}')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (pending.isNotEmpty)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await attempt(context, () => Api.instance.post('/policy-versions/${p['versionId']}/remind'), success: 'Reminder sent to ${pending.length}');
              },
              child: const Text('Remind them'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Policy admin'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => _write(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New policy'),
          ),
        ),
      ]),
      body: Fetch<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => asList(await Api.instance.get('/policies/admin')),
        builder: (context, list, reload) => PageBody(onRefresh: reload, children: [
          if (list.isEmpty) const EmptyView('No policies yet.'),
          for (final p in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('${p['category']} · v${p['version'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    StatusChip(p['status'] as String),
                  ]),
                  if (p['status'] == 'PUBLISHED' && p['requireAck'] == true) ...[
                    gap12,
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (p['audience'] as int) == 0 ? 0 : (p['acked'] as int) / (p['audience'] as int),
                        minHeight: 8,
                        color: C.ink,
                        backgroundColor: C.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${p['acked']} of ${p['audience']} acknowledged', style: const TextStyle(fontSize: 12)),
                  ],
                  gap8,
                  Wrap(spacing: 8, children: [
                    if (p['status'] == 'DRAFT') FilledButton(onPressed: () => _publish(p), child: const Text('Publish')),
                    if (p['status'] == 'PUBLISHED') TextButton(onPressed: () => _write(p), child: const Text('New version')),
                    if (p['status'] == 'DRAFT' && p['version'] != null) TextButton(onPressed: () => _write(p), child: const Text('Edit draft')),
                    if (p['status'] == 'PUBLISHED' && p['requireAck'] == true) TextButton(onPressed: () => _acks(p), child: const Text('Who has read it')),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
