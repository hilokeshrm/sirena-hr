import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Key _key = UniqueKey();

  static String _when(String iso) {
    final t = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM, HH:mm').format(t);
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['readAt'] == null) await Api.instance.post('/notifications/${n['id']}/read').catchError((_) => null);
    if (!mounted) return;
    final link = n['link'] as String?;
    if (link != null && link.startsWith('/')) {
      await context.push(link);
    }
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        TextButton(
          onPressed: () async {
            await attempt(context, () => Api.instance.post('/notifications/read-all'));
            if (mounted) setState(() => _key = UniqueKey());
          },
          child: const Text('Mark all read'),
        ),
      ]),
      body: Fetch<List<Map<String, dynamic>>>(
        key: _key,
        load: () async => asList(await Api.instance.get('/notifications')),
        builder: (context, list, reload) => PageBody(maxWidth: 640, onRefresh: reload, children: [
          if (list.isEmpty) const EmptyView("You're all caught up."),
          for (final n in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                color: n['readAt'] == null ? C.grey : Colors.white,
                onTap: () => _open(n),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: n['readAt'] == null ? C.red : Colors.transparent)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${n['title']}', style: TextStyle(fontWeight: n['readAt'] == null ? FontWeight.w800 : FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(_when(n['createdAt'] as String), style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  if (n['link'] != null) const Icon(Icons.chevron_right, size: 20),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
