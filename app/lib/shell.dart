import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'core/theme.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, {this.permission});
  final String path;
  final String label;
  final IconData icon;
  final String? permission;
}

const _mobileTabs = [
  _Dest('/', 'Home', Icons.home_outlined),
  _Dest('/leave', 'Leave', Icons.event_outlined),
  _Dest('/attendance', 'Check-in', Icons.schedule_outlined),
  _Dest('/food', 'Food', Icons.restaurant_outlined),
  _Dest('/projects', 'Projects', Icons.work_outline),
  _Dest('/me', 'Me', Icons.person_outline),
];

const _sideMain = [
  _Dest('/', 'Home', Icons.home_outlined),
  _Dest('/attendance', 'Check-in', Icons.schedule_outlined),
  _Dest('/food', 'Lunch', Icons.restaurant_outlined),
  _Dest('/leave', 'My leave', Icons.event_outlined),
  _Dest('/leave/calendar', "Who's off", Icons.calendar_month_outlined),
  _Dest('/projects', 'Projects', Icons.work_outline),
  _Dest('/policies', 'Policies', Icons.description_outlined),
  _Dest('/people', 'People', Icons.groups_outlined),
];

const _sideAdmin = [
  _Dest('/leave/approvals', 'Leave approvals', Icons.task_alt_outlined, permission: 'approveLeave'),
  _Dest('/admin/employees', 'Employees', Icons.badge_outlined, permission: 'manageEmployees'),
  _Dest('/admin/attendance', 'Attendance', Icons.fact_check_outlined, permission: 'viewAllAttendance'),
  _Dest('/admin/cafeteria', 'Cafeteria', Icons.lunch_dining_outlined, permission: 'viewMealReport'),
  _Dest('/admin/policies', 'Policy admin', Icons.gavel_outlined, permission: 'managePolicies'),
];

/// Bottom tabs on phones; a sidebar (with admin sections the person is allowed to see) on wide screens.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  bool _active(String path) => path == '/' ? location == '/' : location == path || location.startsWith('$path/');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 1000) return _wide(context);
      final idx = _mobileTabs.lastIndexWhere((d) => _active(d.path));
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx < 0 ? 0 : idx,
          height: 68,
          onDestinationSelected: (i) => context.go(_mobileTabs[i].path),
          destinations: [
            for (final d in _mobileTabs) NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      );
    });
  }

  Widget _wide(BuildContext context) {
    final s = Session.instance;
    final admin = _sideAdmin.where((d) => s.can(d.permission!)).toList();
    Widget item(_Dest d) {
      final on = _active(d.path) && !(d.path == '/leave' && location.startsWith('/leave/'));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: on ? C.grey : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(d.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(d.icon, size: 20, color: on ? C.ink : C.grey),
                const SizedBox(width: 12),
                Text(d.label, style: TextStyle(color: on ? C.ink : C.grey, fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(children: [
        Container(
          width: 240,
          color: C.ink,
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
              child: Align(alignment: Alignment.centerLeft, child: Image.asset('assets/sirena-logo.png', height: 44)),
            ),
            Expanded(
              child: ListView(children: [
                ..._sideMain.map(item),
                if (admin.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 18, 12, 6),
                    child: Text('ADMIN', style: TextStyle(color: C.grey, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                  ...admin.map(item),
                ],
              ]),
            ),
            Material(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.go('/me'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    CircleAvatar(radius: 18, backgroundColor: C.red, child: Text(s.firstName.isEmpty ? '?' : s.firstName[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s.me?['fullName'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text('${s.me?['designation'] ?? ''}', style: const TextStyle(color: C.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}
