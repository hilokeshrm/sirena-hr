import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'features/admin/access_admin.dart';
import 'features/admin/attendance_admin.dart';
import 'features/admin/cafeteria_admin.dart';
import 'features/admin/employees_admin.dart';
import 'features/admin/policies_admin.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/home/home_screen.dart';
import 'features/leave/apply_leave_screen.dart';
import 'features/leave/approvals_screen.dart';
import 'features/leave/calendar_screen.dart';
import 'features/leave/leave_detail_screen.dart';
import 'features/leave/leave_screen.dart';
import 'features/meals/food_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/people/directory_screen.dart';
import 'features/people/person_screen.dart';
import 'features/policies/policies_screen.dart';
import 'features/policies/policy_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/projects/project_screen.dart';
import 'features/projects/projects_screen.dart';
import 'shell.dart';

GoRoute _page(String path, Widget Function(GoRouterState s) build) =>
    GoRoute(path: path, pageBuilder: (context, state) => NoTransitionPage(child: build(state)));

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: Session.instance,
  redirect: (context, state) {
    final s = Session.instance;
    final path = state.uri.path;
    final public = path == '/login' || path.startsWith('/signup/');
    if (!s.ready) return path == '/splash' ? null : '/splash';
    if (!s.signedIn) return public ? null : '/login';
    if (s.mustChangePassword) return path == '/set-password' ? null : '/set-password';
    if (public || path == '/splash' || path == '/set-password') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/set-password', builder: (_, __) => const ChangePasswordScreen()),
    GoRoute(path: '/signup/:token', builder: (_, s) => SignupScreen(token: s.pathParameters['token']!)),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        _page('/', (_) => const HomeScreen()),
        _page('/attendance', (_) => const AttendanceScreen()),
        _page('/food', (_) => const FoodScreen()),
        _page('/leave', (_) => const LeaveScreen()),
        _page('/leave/apply', (_) => const ApplyLeaveScreen()),
        _page('/leave/approvals', (_) => const ApprovalsScreen()),
        _page('/leave/calendar', (_) => const CalendarScreen()),
        _page('/leave/requests/:id', (s) => LeaveDetailScreen(id: s.pathParameters['id']!)),
        _page('/projects', (_) => const ProjectsScreen()),
        _page('/projects/:id', (s) => ProjectScreen(id: s.pathParameters['id']!)),
        _page('/policies', (_) => const PoliciesScreen()),
        _page('/policies/:id', (s) => PolicyScreen(id: s.pathParameters['id']!)),
        _page('/people', (_) => const DirectoryScreen()),
        _page('/people/:id', (s) => PersonScreen(id: s.pathParameters['id']!)),
        _page('/me', (_) => const ProfileScreen()),
        _page('/notifications', (_) => const NotificationsScreen()),
        _page('/admin/employees', (_) => const EmployeesAdmin()),
        _page('/admin/attendance', (_) => const AttendanceAdmin()),
        _page('/admin/cafeteria', (_) => const CafeteriaAdmin()),
        _page('/admin/policies', (_) => const PoliciesAdmin()),
        _page('/admin/access', (_) => const AccessAdmin()),
      ],
    ),
  ],
);

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: C.ink,
        body: Center(child: CircularProgressIndicator(color: C.red)),
      );
}
