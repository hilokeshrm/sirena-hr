import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _roleLabels = {'EMPLOYEE': 'Employee', 'HR': 'HR', 'HR_ADMIN': 'HR Admin', 'FINANCE': 'Finance'};

/// Super admin: which role may do what, plus per-person exceptions.
class AccessAdmin extends StatefulWidget {
  const AccessAdmin({super.key});

  @override
  State<AccessAdmin> createState() => _AccessAdminState();
}

class _AccessAdminState extends State<AccessAdmin> {
  Key _key = UniqueKey();
  // Latest matrix returned by a change; null means use what Fetch loaded.
  Map<String, dynamic>? _saved;
  final _busy = <String>{};

  void _reload() => setState(() {
        _saved = null;
        _key = UniqueKey();
      });

  Future<void> _toggle(String role, String permission, bool enabled) async {
    final id = '$role:$permission';
    setState(() => _busy.add(id));
    final res = await attempt(context, () => Api.instance.put('/access/roles/$role/$permission', {'enabled': enabled}));
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (res != null) _saved = asMap(res);
    });
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text('Every role goes back to the standard access. Exceptions for individual people are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await attempt(context, () => Api.instance.post('/access/roles/reset'), success: 'Access reset to defaults');
    if (res != null && mounted) setState(() => _saved = asMap(res));
  }

  Future<void> _person(List<Map<String, dynamic>> permissions, [String? employeeId]) async {
    var id = employeeId;
    if (id == null) {
      final people = await attempt(context, () async => asList(await Api.instance.get('/employees')));
      if (people == null || !mounted) return;
      id = await showDialog<String>(context: context, builder: (_) => _PickPerson(people));
      if (id == null || !mounted) return;
    }
    await showDialog<void>(context: context, builder: (_) => _PersonAccess(employeeId: id!, permissions: permissions));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roles & access'), actions: [
        TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Reset')),
      ]),
      body: Fetch<Map<String, dynamic>>(
        key: _key,
        load: () async => asMap(await Api.instance.get('/access/permissions')),
        builder: (context, loaded, reload) {
          final m = _saved ?? loaded;
          final permissions = asList(m['permissions']);
          final roles = (m['roles'] as List).cast<String>();
          final grants = asMap(m['grants']).map((k, v) => MapEntry(k, (v as List).cast<String>().toSet()));
          final defaults = asMap(m['defaults']).map((k, v) => MapEntry(k, (v as List).cast<String>().toSet()));
          final overrides = asList(m['overrides']);
          final labelOf = {for (final p in permissions) p['key'] as String: p['label'] as String};
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final p in permissions) {
            groups.putIfAbsent(p['group'] as String, () => []).add(p);
          }

          return LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;

            Widget toggle(String role, String key) {
              final on = grants[role]?.contains(key) ?? false;
              final changed = on != (defaults[role]?.contains(key) ?? false);
              final busy = _busy.contains('$role:$key');
              return Column(mainAxisSize: MainAxisSize.min, children: [
                if (!wide) Text(_roleLabels[role] ?? prettyEnum(role), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                Switch(
                  value: on,
                  activeTrackColor: C.red,
                  onChanged: busy ? null : (v) => _toggle(role, key, v),
                ),
                Text(changed ? 'changed' : '', style: const TextStyle(fontSize: 10, color: C.red, fontWeight: FontWeight.w700)),
              ]);
            }

            Widget row(Map<String, dynamic> p) {
              final key = p['key'] as String;
              final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['label']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${p['description']}', style: const TextStyle(fontSize: 12)),
              ]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: wide
                      ? Row(children: [
                          Expanded(child: text),
                          for (final r in roles) SizedBox(width: 96, child: toggle(r, key)),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          text,
                          gap8,
                          Row(children: [for (final r in roles) Expanded(child: toggle(r, key))]),
                        ]),
                ),
              );
            }

            return PageBody(maxWidth: 1000, onRefresh: () async => _reload(), children: [
              const Panel(
                color: C.grey,
                child: Text(
                  'Turn access on or off for each role. Changes apply straight away. '
                  'Super admins always have full access, and nobody can approve their own leave. '
                  'HR permissions about people and leave only reach their own location.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              gap12,
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                  child: Row(children: [
                    const Expanded(child: SizedBox()),
                    for (final r in roles)
                      SizedBox(
                        width: 96,
                        child: Text(_roleLabels[r] ?? prettyEnum(r), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                  ]),
                ),
              for (final g in groups.entries) ...[
                SectionTitle(g.key),
                for (final p in g.value) row(p),
              ],
              gap16,
              SectionTitle(
                'Exceptions for individual people',
                trailing: TextButton.icon(onPressed: () => _person(permissions), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add')),
              ),
              if (overrides.isEmpty) const EmptyView('No exceptions. Everyone has their role’s access.'),
              for (final o in overrides)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => _person(permissions, asMap(o['employee'])['id'] as String),
                    child: Row(children: [
                      Avatar(asMap(o['employee'])['fullName'] as String, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${asMap(o['employee'])['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${labelOf[o['permission']] ?? o['permission']} · ${prettyEnum('${asMap(o['employee'])['role']}')}', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                      StatusChip(o['granted'] == true ? 'APPROVED' : 'CANCELLED', label: o['granted'] == true ? 'Granted' : 'Removed'),
                    ]),
                  ),
                ),
            ]);
          });
        },
      ),
    );
  }
}

class _PickPerson extends StatefulWidget {
  const _PickPerson(this.people);
  final List<Map<String, dynamic>> people;

  @override
  State<_PickPerson> createState() => _PickPersonState();
}

class _PickPersonState extends State<_PickPerson> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final hits = widget.people.where((p) => '${p['fullName']} ${p['code']}'.toLowerCase().contains(q)).take(50).toList();
    return AlertDialog(
      title: const Text('Choose a person'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(decoration: inputDeco('Search name or code'), autofocus: true, onChanged: (v) => setState(() => _q = v)),
          gap8,
          Expanded(
            child: ListView(children: [
              for (final p in hits)
                ListTile(
                  leading: Avatar(p['fullName'] as String, size: 32),
                  title: Text('${p['fullName']}'),
                  subtitle: Text('${p['code']} · ${p['designation'] ?? ''}'),
                  onTap: () => Navigator.pop(context, p['id'] as String),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// One person's access: role default, or granted / removed just for them.
class _PersonAccess extends StatefulWidget {
  const _PersonAccess({required this.employeeId, required this.permissions});
  final String employeeId;
  final List<Map<String, dynamic>> permissions;

  @override
  State<_PersonAccess> createState() => _PersonAccessState();
}

class _PersonAccessState extends State<_PersonAccess> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/access/people/${widget.employeeId}').then(
          (r) => mounted ? setState(() => _data = asMap(r)) : null,
          onError: (Object e) => mounted ? setState(() => _error = '$e') : null,
        );
  }

  Future<void> _set(String permission, String choice) async {
    setState(() => _busy = true);
    final path = '/access/people/${widget.employeeId}/$permission';
    final res = await attempt(
      context,
      () => choice == 'role' ? Api.instance.delete(path) : Api.instance.put(path, {'granted': choice == 'grant'}),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res != null) _data = asMap(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final emp = d == null ? null : asMap(d['employee']);
    final superAdmin = emp?['role'] == 'SUPER_ADMIN';
    return AlertDialog(
      title: Text(emp == null ? 'Access' : '${emp['fullName']}'),
      content: SizedBox(
        width: 560,
        child: d == null
            ? (_error != null ? Text(_error!) : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: C.red))))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${emp!['code']} · ${prettyEnum('${emp['role']}')}', style: const TextStyle(fontSize: 13)),
                  gap12,
                  if (superAdmin)
                    const Text('Super admins always have full access.')
                  else
                    for (final p in widget.permissions) _row(p, d),
                ]),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }

  Widget _row(Map<String, dynamic> p, Map<String, dynamic> d) {
    final key = p['key'] as String;
    final fromRole = (d['roleGrants'] as List).contains(key);
    final override = asList(d['overrides']).where((o) => o['permission'] == key).firstOrNull;
    final choice = override == null ? 'role' : (override['granted'] == true ? 'grant' : 'revoke');
    final has = (d['effective'] as List).contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(has ? Icons.check_circle : Icons.remove_circle_outline, size: 18, color: has ? C.ink : C.red),
          const SizedBox(width: 8),
          Expanded(child: Text('${p['label']}', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'role', label: Text('Role (${fromRole ? 'on' : 'off'})')),
            const ButtonSegment(value: 'grant', label: Text('Grant')),
            const ButtonSegment(value: 'revoke', label: Text('Remove')),
          ],
          selected: {choice},
          onSelectionChanged: _busy ? null : (s) => _set(key, s.first),
        ),
      ]),
    );
  }
}
