import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class _HomeData {
  _HomeData(this.today, this.lunch, this.balances, this.tasks, this.policies, this.approvals, this.unread);
  final Map<String, dynamic> today;
  final Map<String, dynamic>? lunch;
  final List<Map<String, dynamic>> balances;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> policies;
  final List<Map<String, dynamic>> approvals;
  final int unread;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<_HomeData> _load() async {
    final s = Session.instance;
    final t = todayYmd();
    final r = await Future.wait<dynamic>([
      Api.instance.get('/attendance/today'),
      Api.instance.get('/meals', {'from': t, 'to': t}),
      Api.instance.get('/leave/balances'),
      Api.instance.get('/tasks/mine'),
      Api.instance.get('/policies'),
      s.can('approveLeave') ? Api.instance.get('/leave/requests', {'scope': 'approvals'}) : Future<dynamic>.value(<dynamic>[]),
      Api.instance.get('/notifications'),
    ]);
    final lunch = asList(r[1]);
    return _HomeData(
      asMap(r[0]),
      lunch.isEmpty ? null : lunch.first,
      asList(r[2]),
      asList(r[3]),
      asList(r[4]).where((p) => p['needsAck'] == true).toList(),
      asList(r[5]),
      asList(r[6]).where((n) => n['readAt'] == null).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return Scaffold(
      body: SafeArea(
        child: Fetch<_HomeData>(
          load: _load,
          builder: (context, d, reload) {
            final rec = d.today['record'] as Map?;
            final checkedIn = rec != null && rec['checkOutAt'] == null;
            final dueToday = d.tasks.where((t) => t['dueDate'] != null && (t['dueDate'] as String).compareTo(todayYmd()) <= 0).toList();
            return PageBody(
              onRefresh: reload,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(DateFormat('EEEE, d MMMM').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Hello, ${s.firstName}', style: display(26)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                    icon: Badge(isLabelVisible: d.unread > 0, label: Text('${d.unread}'), backgroundColor: C.red, child: const Icon(Icons.notifications_none)),
                  ),
                ]),
                gap16,
                // Today
                Panel(
                  color: C.ink,
                  padding: const EdgeInsets.all(18),
                  onTap: () => context.go('/attendance'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TODAY', style: TextStyle(color: C.grey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    gap8,
                    if (d.today['onLeave'] == true)
                      Text("You're on leave today", style: display(26, color: Colors.white))
                    else if (rec == null)
                      Text('Not checked in yet', style: display(26, color: Colors.white))
                    else
                      Text(durationSince(rec['checkInAt'] as String, rec['checkOutAt'] as String?), style: display(38, color: Colors.white)),
                    if (rec != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${rec['mode'] == 'WFH' ? 'Working from home' : 'In office'} since ${clock(rec['checkInAt'] as String)}'
                        '${rec['method'] == 'WIFI' ? ' · office Wi-Fi' : rec['method'] == 'GPS' ? ' · office location' : ''}${rec['checkOutAt'] != null ? ' · checked out ${clock(rec['checkOutAt'] as String)}' : ''}',
                        style: const TextStyle(color: C.grey),
                      ),
                    ],
                    gap12,
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: checkedIn ? Colors.white : C.red, foregroundColor: checkedIn ? C.red : Colors.white, minimumSize: const Size(0, 44)),
                        onPressed: () => context.go('/attendance'),
                        child: Text(checkedIn ? 'Check out' : 'Check in'),
                      ),
                    ),
                  ]),
                ),
                gap12,
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _LunchCard(lunch: d.lunch)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Panel(
                      onTap: () => context.go('/leave'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Leave left', style: TextStyle(fontWeight: FontWeight.w700)),
                        gap8,
                        Text(
                          num1(d.balances.where((b) => b['unlimited'] != true && ['CL', 'SL', 'EL', 'CO'].contains(b['code'])).fold<double>(0, (a, b) => a + (b['available'] as num).toDouble())),
                          style: display(30),
                        ),
                        const Text('days · casual, sick, earned, comp-off', style: TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
                ]),
                gap16,
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _Quick(icon: Icons.add, label: 'Apply leave', onTap: () => context.push('/leave/apply'), primary: true),
                  _Quick(icon: Icons.work_outline, label: 'Projects', onTap: () => context.go('/projects')),
                  _Quick(icon: Icons.description_outlined, label: 'Policies', onTap: () => context.push('/policies')),
                  _Quick(icon: Icons.groups_outlined, label: 'People', onTap: () => context.push('/people')),
                  _Quick(icon: Icons.calendar_month_outlined, label: "Who's off", onTap: () => context.push('/leave/calendar')),
                ]),
                gap16,
                const SectionTitle('To do'),
                if (d.approvals.isNotEmpty)
                  _Todo(icon: Icons.task_alt, title: '${d.approvals.length} leave request${d.approvals.length == 1 ? '' : 's'} to review', sub: d.approvals.map((a) => (a['employee'] as Map)['fullName']).take(3).join(', '), onTap: () => context.push('/leave/approvals')),
                for (final p in d.policies)
                  _Todo(icon: Icons.description_outlined, title: 'Read ${p['title']} v${p['version']}', sub: 'Tap to acknowledge', onTap: () => context.push('/policies/${p['id']}')),
                if (dueToday.isNotEmpty)
                  _Todo(icon: Icons.work_outline, title: '${dueToday.length} task${dueToday.length == 1 ? '' : 's'} due', sub: dueToday.map((t) => t['title']).take(2).join(' · '), onTap: () => context.go('/projects')),
                if (d.approvals.isEmpty && d.policies.isEmpty && dueToday.isEmpty) const EmptyView("You're all caught up."),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LunchCard extends StatelessWidget {
  const _LunchCard({required this.lunch});
  final Map<String, dynamic>? lunch;

  @override
  Widget build(BuildContext context) {
    final b = lunch?['booking'] as Map?;
    final choice = b?['choice'] as String?;
    String title;
    String sub;
    if (lunch == null) {
      title = 'No lunch today';
      sub = 'Weekend';
    } else if (choice == 'VEG' || choice == 'NON_VEG') {
      title = choice == 'VEG' ? 'Veg booked' : 'Non-veg booked';
      sub = 'Pass ${b?['passCode']}';
    } else if (lunch!['canBook'] == true) {
      title = 'Not booked';
      sub = 'Book before cut-off';
    } else {
      title = 'No lunch';
      sub = '${lunch!['reason'] ?? ''}';
    }
    return Panel(
      color: C.grey,
      onTap: () => context.go('/food'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Today's lunch", style: TextStyle(fontWeight: FontWeight.w700)),
        gap8,
        Row(children: [
          if (choice == 'VEG' || choice == 'NON_VEG') ...[FoodMark(veg: choice == 'VEG'), const SizedBox(width: 8)],
          Flexible(child: Text(title, style: display(20))),
        ]),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 78,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: primary ? C.red : C.grey, borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: primary ? Colors.white : C.ink),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _Todo extends StatelessWidget {
  const _Todo({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: C.red, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}
