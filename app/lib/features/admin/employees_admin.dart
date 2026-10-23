import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// HR: add people, send sign-up links, edit work details.
class EmployeesAdmin extends StatefulWidget {
  const EmployeesAdmin({super.key});

  @override
  State<EmployeesAdmin> createState() => _EmployeesAdminState();
}

class _EmployeesAdminState extends State<EmployeesAdmin> {
  Key _key = UniqueKey();

  Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> _load() async {
    final r = await Future.wait<dynamic>([Api.instance.get('/employees'), Api.instance.get('/lookups')]);
    return (asList(r[0]), asMap(r[1]));
  }

  Future<void> _invite(Map<String, dynamic> e) async {
    final res = await attempt(context, () => Api.instance.post('/auth/invites', {'employeeId': e['id']}));
    if (res == null || !mounted) return;
    // The web app uses hash routing, so the link is <site>/#/signup/<token>.
    final link = '${Uri.base.origin}/#${asMap(res)['path']}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign-up link for ${e['fullName']}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Send this to their work email. It works once and expires in 7 days.'),
          gap12,
          Panel(color: C.grey, child: SelectableText(link, style: const TextStyle(fontSize: 13))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              showSnack(context, 'Link copied');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _form(Map<String, dynamic> lookups, [Map<String, dynamic>? existing]) async {
    Map<String, dynamic>? e;
    if (existing != null) {
      e = asMap(await Api.instance.get('/employees/${existing['id']}'));
      if (!mounted) return;
    }
    final name = TextEditingController(text: e?['fullName'] as String? ?? '');
    final email = TextEditingController(text: e?['email'] as String? ?? '');
    final designation = TextEditingController(text: e?['designation'] as String? ?? '');
    final phone = TextEditingController(text: e?['phone'] as String? ?? '');
    String? dept = e?['departmentId'] as String?;
    String? loc = e?['locationId'] as String?;
    String? manager = e?['managerId'] as String?;
    String workMode = e?['workMode'] as String? ?? 'HYBRID';
    String type = e?['employmentType'] as String? ?? 'FULL_TIME';
    String status = e?['status'] as String? ?? 'ONBOARDING';
    DateTime? joined = e?['joinedOn'] != null ? day(e!['joinedOn'] as String) : null;

    DropdownButtonFormField<String?> pick(String label, String? value, List<Map<String, dynamic>> items, String key, void Function(String?) onChanged) =>
        DropdownButtonFormField<String?>(
          value: value,
          isExpanded: true,
          decoration: inputDeco(label),
          items: [const DropdownMenuItem(value: null, child: Text('—')), for (final i in items) DropdownMenuItem(value: i['id'] as String, child: Text('${i[key]}'))],
          onChanged: onChanged,
        );

    DropdownButtonFormField<String> pickEnum(String label, String value, List<String> values, void Function(String) onChanged) => DropdownButtonFormField<String>(
          value: value,
          decoration: inputDeco(label),
          items: [for (final v in values) DropdownMenuItem(value: v, child: Text(prettyEnum(v)))],
          onChanged: (v) => onChanged(v!),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'Add employee' : 'Edit ${existing['fullName']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, decoration: inputDeco('Full name')),
                gap12,
                TextField(controller: email, decoration: inputDeco('Work email (@sirenatech.com)'), keyboardType: TextInputType.emailAddress),
                gap12,
                TextField(controller: designation, decoration: inputDeco('Designation')),
                gap12,
                TextField(controller: phone, decoration: inputDeco('Phone'), keyboardType: TextInputType.phone),
                gap12,
                pick('Department', dept, asList(lookups['departments']), 'name', (v) => set(() => dept = v)),
                gap12,
                pick('Location', loc, asList(lookups['locations']), 'name', (v) => set(() => loc = v)),
                gap12,
                pick('Reports to', manager, asList(lookups['managers']).where((m) => m['id'] != existing?['id']).toList(), 'fullName', (v) => set(() => manager = v)),
                gap12,
                pickEnum('Work mode', workMode, ['OFFICE', 'HYBRID', 'REMOTE'], (v) => set(() => workMode = v)),
                gap12,
                pickEnum('Employment type', type, ['FULL_TIME', 'CONTRACT', 'INTERN', 'CONSULTANT'], (v) => set(() => type = v)),
                gap12,
                pickEnum('Status', status, ['ONBOARDING', 'ACTIVE', 'ON_NOTICE', 'EXITED'], (v) => set(() => status = v)),
                gap12,
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(joined == null ? 'Joining date' : 'Joined ${niceDay(ymd(joined!))}'),
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: joined ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) set(() => joined = d);
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(existing == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    String? blank(String s) => s.trim().isEmpty ? null : s.trim();
    final body = <String, dynamic>{
      'fullName': name.text.trim(),
      'email': email.text.trim(),
      if (blank(designation.text) != null) 'designation': designation.text.trim(),
      if (blank(phone.text) != null) 'phone': phone.text.trim(),
      if (dept != null) 'departmentId': dept,
      if (loc != null) 'locationId': loc,
      if (manager != null) 'managerId': manager,
      'workMode': workMode,
      'employmentType': type,
      'status': status,
      if (joined != null) 'joinedOn': ymd(joined!),
    };
    final res = await attempt(
      context,
      () => existing == null ? Api.instance.post('/employees', body) : Api.instance.patch('/employees/${existing['id']}', body),
      success: existing == null ? 'Employee added' : 'Saved',
    );
    if (res == null || !mounted) return;
    setState(() => _key = UniqueKey());
    if (existing == null) await _invite(asMap(res));
  }

  @override
  Widget build(BuildContext context) {
    return Fetch<(List<Map<String, dynamic>>, Map<String, dynamic>)>(
      key: _key,
      load: _load,
      builder: (context, data, reload) {
        final (people, lookups) = data;
        return Scaffold(
          appBar: AppBar(title: const Text('Employees'), actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => _form(lookups),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add'),
              ),
            ),
          ]),
          body: PageBody(onRefresh: reload, children: [
            Text('${people.length} people', style: const TextStyle(fontWeight: FontWeight.w700)),
            gap8,
            for (final p in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => context.push('/people/${p['id']}'),
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(children: [
                    Avatar(p['fullName'] as String, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${p['code']} · ${p['designation'] ?? '—'} · ${(p['location'] as Map?)?['name'] ?? '—'}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    if (p['status'] != 'ACTIVE') StatusChip(p['status'] as String),
                    PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _form(lookups, p) : _invite(p),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit work details')),
                        PopupMenuItem(value: 'invite', child: Text('Create sign-up link')),
                      ],
                    ),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
