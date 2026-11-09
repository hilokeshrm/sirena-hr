import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
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
  // Bumped when role grants change, so open person panels reload.
  int _version = 0;

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
      if (res != null) {
        _saved = asMap(res);
        _version++;
      }
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
    if (res != null && mounted) {
      setState(() {
        _saved = asMap(res);
        _version++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roles & access'), actions: [
        // Resetting every role is a super-admin action; the server refuses it for anyone else too.
        if (Session.instance.can('admin'))
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
              _People(labelOf: labelOf, version: _version),
            ]);
          });
        },
      ),
    );
  }
}

const _allRoles = ['EMPLOYEE', 'HR', 'HR_ADMIN', 'FINANCE', 'SUPER_ADMIN'];

String _roleLabel(String r) => r == 'SUPER_ADMIN' ? 'Super Admin' : (_roleLabels[r] ?? prettyEnum(r));

/// Everyone still working here: change their role, and open one to see and adjust exactly what they can do.
class _People extends StatefulWidget {
  const _People({required this.labelOf, required this.version});
  final Map<String, String> labelOf;
  final int version;

  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  Key _key = UniqueKey();
  String _q = '';
  String? _role;
  String? _dept;
  String? _open;
  // Role and exception changes made here since the list loaded, by employee id.
  final _roles = <String, String>{};
  final _custom = <String, bool>{};
  int _detailVersion = 0;

  Future<void> _changeRole(Map<String, dynamic> p, String role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Make ${p['fullName']} ${_roleLabel(role)}?'),
        content: Text(role == 'SUPER_ADMIN'
            ? 'Super admins have full access to everything, including this screen. Their personal exceptions are removed.'
            : 'They get ${_roleLabel(role)} access straight away, plus any personal exceptions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change role')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = p['id'] as String;
    final res = await attempt(context, () => Api.instance.patch('/access/people/$id', {'role': role}), success: 'Role changed');
    if (res == null || !mounted) return;
    final d = asMap(res);
    setState(() {
      _roles[id] = asMap(d['employee'])['role'] as String;
      _custom[id] = (d['overrides'] as List).isNotEmpty;
      _detailVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Fetch<List<Map<String, dynamic>>>(
      key: _key,
      load: () async => asList(await Api.instance.get('/access/people')),
      builder: (context, people, reload) {
        final depts = {
          for (final p in people)
            if (p['department'] != null) asMap(p['department'])['name'] as String,
        }.toList()
          ..sort();
        String roleOf(Map<String, dynamic> p) => _roles[p['id']] ?? p['role'] as String;
        bool customOf(Map<String, dynamic> p) => _custom[p['id']] ?? (p['overrides'] as List).isNotEmpty;
        final q = _q.toLowerCase();
        final shown = people.where((p) {
          final dept = p['department'] == null ? null : asMap(p['department'])['name'];
          return '${p['fullName']} ${p['email']} ${p['code']}'.toLowerCase().contains(q) &&
              (_role == null || roleOf(p) == _role) &&
              (_dept == null || dept == _dept);
        }).toList();
        final customCount = people.where(customOf).length;

        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 640;
          final roleFilter = DropdownButtonFormField<String?>(
            initialValue: _role,
            isExpanded: true,
            decoration: inputDeco('Role'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All roles')),
              for (final r in _allRoles) DropdownMenuItem(value: r, child: Text(_roleLabel(r))),
            ],
            onChanged: (v) => setState(() => _role = v),
          );
          final deptFilter = DropdownButtonFormField<String?>(
            initialValue: _dept,
            isExpanded: true,
            decoration: inputDeco('Department'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All departments')),
              for (final d in depts) DropdownMenuItem(value: d, child: Text(d)),
            ],
            onChanged: (v) => setState(() => _dept = v),
          );

          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(
              'People',
              trailing: IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() {
                  _roles.clear();
                  _custom.clear();
                  _key = UniqueKey();
                }),
              ),
            ),
            Text(
              '${people.length} people · $customCount with personal exceptions. Open someone to see exactly what they can and can’t do.',
              style: const TextStyle(fontSize: 12),
            ),
            gap12,
            TextField(decoration: inputDeco('Search name, email or code', suffix: const Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
            gap8,
            if (wide)
              Row(children: [Expanded(child: roleFilter), const SizedBox(width: 8), Expanded(child: deptFilter)])
            else ...[
              roleFilter,
              gap8,
              deptFilter,
            ],
            gap12,
            if (shown.isEmpty) const EmptyView('Nobody matches.'),
            for (final p in shown) _personTile(p, roleOf(p), customOf(p), wide),
          ]);
        });
      },
    );
  }

  Widget _personTile(Map<String, dynamic> p, String role, bool custom, bool wide) {
    final id = p['id'] as String;
    final self = id == Session.instance.id;
    final open = _open == id;
    final dept = p['department'] == null ? null : asMap(p['department'])['name'] as String;
    final loc = p['location'] == null ? null : asMap(p['location'])['name'] as String;
    final roleBox = DropdownButton<String>(
      value: role,
      isDense: true,
      underline: const SizedBox(),
      items: [
        for (final r in _allRoles) DropdownMenuItem(value: r, child: Text(_roleLabel(r), style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
      onChanged: self ? null : (r) => r == null || r == role ? null : _changeRole(p, r),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text('${p['fullName']}', style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
        if (custom) ...[const SizedBox(width: 6), const StatusChip('PENDING_HR', label: 'Custom')],
        if (self) ...[const SizedBox(width: 6), const StatusChip('', label: 'You')],
      ]),
      Text('${p['email']}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      Text([dept ?? 'No department', if (loc != null) loc].join(' · '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _open = open ? null : id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Avatar(p['fullName'] as String, size: 36),
                const SizedBox(width: 12),
                Expanded(child: wide ? info : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, roleBox])),
                if (wide) roleBox,
                Icon(open ? Icons.expand_less : Icons.expand_more),
              ]),
            ),
          ),
          if (open)
            _PersonPermissions(
              key: ValueKey('$id:${widget.version}:$_detailVersion'),
              employeeId: id,
              self: self,
              labelOf: widget.labelOf,
              onCustomChanged: (c) => setState(() => _custom[id] = c),
            ),
        ]),
      ),
    );
  }
}

/// Every permission for one person: what they can or can't do, with a switch to change it just for them.
class _PersonPermissions extends StatefulWidget {
  const _PersonPermissions({super.key, required this.employeeId, required this.self, required this.labelOf, required this.onCustomChanged});
  final String employeeId;
  final bool self;
  final Map<String, String> labelOf;
  final ValueChanged<bool> onCustomChanged;

  @override
  State<_PersonPermissions> createState() => _PersonPermissionsState();
}

class _PersonPermissionsState extends State<_PersonPermissions> {
  Map<String, dynamic>? _data;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    Api.instance.get('/access/people/${widget.employeeId}').then(
          (r) => mounted ? setState(() => _data = asMap(r)) : null,
          onError: (Object e) => mounted ? setState(() => _error = '$e') : null,
        );
  }

  /// Switching back to the role's default (or "Reset to role") clears the exception; anything else stores one.
  Future<void> _set(Map<String, dynamic> p, bool? on) async {
    final key = p['key'] as String;
    final path = '/access/people/${widget.employeeId}/$key';
    final clear = on == null || on == p['fromRole'];
    setState(() => _busy.add(key));
    final res = await attempt(context, () => clear ? Api.instance.delete(path) : Api.instance.put(path, {'granted': on}));
    if (!mounted) return;
    setState(() {
      _busy.remove(key);
      if (res != null) _data = asMap(res);
    });
    if (res != null) widget.onCustomChanged((asMap(res)['overrides'] as List).isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _error != null ? Text(_error!) : const Center(child: CircularProgressIndicator(color: C.red)),
      );
    }
    final superAdmin = asMap(d['employee'])['role'] == 'SUPER_ADMIN';
    final locked = superAdmin || widget.self;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.grey))),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (locked)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              superAdmin ? 'Super admins always have full access.' : 'You can’t change your own access.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        for (final p in asList(d['permissions'])) _row(p, locked),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> p, bool locked) {
    final key = p['key'] as String;
    final has = p['has'] == true;
    final overridden = p['overridden'] == true;
    final busy = _busy.contains(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(has ? Icons.check_circle : Icons.block, size: 18, color: has ? C.ink : Colors.black38),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(widget.labelOf[key] ?? key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              if (overridden) const StatusChip('PENDING_HR', label: 'Custom'),
            ]),
            Text('${p['effect']}', style: const TextStyle(fontSize: 12)),
            if (overridden) Text('Role default: ${p['fromRole'] == true ? 'on' : 'off'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
        Column(children: [
          Switch(value: has, activeTrackColor: C.red, onChanged: locked || busy ? null : (v) => _set(p, v)),
          if (overridden && !locked)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: busy ? null : () => _set(p, null),
              child: const Text('Reset to role', style: TextStyle(fontSize: 11)),
            ),
        ]),
      ]),
    );
  }
}
