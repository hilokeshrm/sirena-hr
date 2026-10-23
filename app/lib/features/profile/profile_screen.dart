import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../people/person_screen.dart';

/// My profile: contact details I can edit, quick links, password, sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Key _key = UniqueKey();

  Future<void> _edit(Map<String, dynamic> e) async {
    final fields = {
      'preferredName': 'Preferred name',
      'phone': 'Phone',
      'personalEmail': 'Personal email',
      'address': 'Address',
      'bloodGroup': 'Blood group',
      'emergencyName': 'Emergency contact name',
      'emergencyRelation': 'Relation',
      'emergencyPhone': 'Emergency phone',
    };
    final ctrls = {for (final k in fields.keys) k: TextEditingController(text: (e[k] ?? '') as String)};
    String? food = e['foodPref'] as String?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Edit my details'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final f in fields.entries) ...[
                  TextField(controller: ctrls[f.key], decoration: inputDeco(f.value), maxLines: f.key == 'address' ? 3 : 1, minLines: 1),
                  gap12,
                ],
                const Text('Food preference', style: TextStyle(fontWeight: FontWeight.w700)),
                gap8,
                SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: 'VEG', label: Text('Veg'), icon: FoodMark(veg: true, size: 16)),
                    ButtonSegment(value: 'NON_VEG', label: Text('Non-veg'), icon: FoodMark(veg: false, size: 16)),
                  ],
                  selected: {if (food != null) food!},
                  onSelectionChanged: (v) => set(() => food = v.isEmpty ? null : v.first),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    // Only send what changed; blank fields are left alone.
    final body = <String, dynamic>{
      for (final k in fields.keys)
        if (ctrls[k]!.text.trim() != (e[k] ?? '') && ctrls[k]!.text.trim().isNotEmpty) k: ctrls[k]!.text.trim(),
      if (food != null && food != e['foodPref']) 'foodPref': food,
    };
    if (body.isEmpty) return;
    final r = await attempt(context, () => Api.instance.patch('/employees/${Session.instance.id}', body), success: 'Saved');
    if (r != null) {
      await Session.instance.refresh();
      if (mounted) setState(() => _key = UniqueKey());
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: current, obscureText: true, decoration: inputDeco('Current password')),
          gap12,
          TextField(controller: next, obscureText: true, decoration: inputDeco('New password (10+ characters)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await attempt(context, () => Api.instance.post('/auth/change-password', {'currentPassword': current.text, 'newPassword': next.text}), success: 'Password changed');
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final links = <(String, String, IconData, String?)>[
      ('/people', 'People', Icons.groups_outlined, null),
      ('/policies', 'Policies', Icons.article_outlined, null),
      ('/leave/calendar', "Who's off", Icons.calendar_month_outlined, null),
      ('/notifications', 'Notifications', Icons.notifications_none, null),
      ('/leave/approvals', 'Leave approvals', Icons.task_alt, 'approveLeave'),
      ('/admin/employees', 'Employees', Icons.badge_outlined, 'manageEmployees'),
      ('/admin/attendance', 'Attendance', Icons.fact_check_outlined, 'viewAllAttendance'),
      ('/admin/cafeteria', 'Cafeteria', Icons.lunch_dining_outlined, 'viewMealReport'),
      ('/admin/policies', 'Policy admin', Icons.gavel_outlined, 'managePolicies'),
    ].where((l) => l.$4 == null || s.can(l.$4!)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: Fetch<Map<String, dynamic>>(
        key: _key,
        load: () async => asMap(await Api.instance.get('/employees/${s.id}')),
        builder: (context, e, reload) => PageBody(maxWidth: 640, onRefresh: reload, children: [
          Panel(
            color: C.ink,
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Avatar(e['fullName'] as String, size: 64, dark: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['preferredName'] ?? e['fullName']}', style: display(24, color: Colors.white)),
                  Text('${e['designation'] ?? ''}', style: const TextStyle(color: Colors.white)),
                  Text('${e['code']} · ${prettyEnum('${e['role'] ?? 'EMPLOYEE'}')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          gap16,
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.15,
            children: [
              for (final l in links)
                Panel(
                  color: C.grey,
                  padding: const EdgeInsets.all(10),
                  onTap: () => context.push(l.$1),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(l.$3, size: 24),
                    const SizedBox(height: 6),
                    Text(l.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          ),
          gap16,
          SectionTitle('My details', trailing: TextButton.icon(onPressed: () => _edit(e), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'))),
          InfoRows({
            'Work email': e['email'],
            'Phone': e['phone'],
            'Personal email': e['personalEmail'],
            'Food': e['foodPref'] == null ? null : (e['foodPref'] == 'VEG' ? 'Veg' : 'Non-veg'),
            'Blood group': e['bloodGroup'],
            'Address': e['address'],
            'Emergency contact': e['emergencyName'] == null ? null : '${e['emergencyName']} (${e['emergencyRelation'] ?? ''}) ${e['emergencyPhone'] ?? ''}',
          }),
          gap16,
          const SectionTitle('Work'),
          InfoRows({
            'Department': (e['department'] as Map?)?['name'],
            'Location': (e['location'] as Map?)?['name'],
            'Reports to': (e['manager'] as Map?)?['fullName'],
            'Joined': e['joinedOn'] == null ? null : niceDay(e['joinedOn'] as String),
          }),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Work details are managed by HR. Ask them if something is wrong.', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: _changePassword, icon: const Icon(Icons.lock_outline, size: 18), label: const Text('Change password')),
          gap8,
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: C.red),
            onPressed: () => Session.instance.logout(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ]),
      ),
    );
  }
}
