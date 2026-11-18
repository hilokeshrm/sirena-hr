import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Everything the app has recorded: who signed in, what changed, who was locked out.
/// Open to whoever has the "View audit log" permission; by default that is super admins only.
class ActivityAdmin extends StatefulWidget {
  const ActivityAdmin({super.key});

  @override
  State<ActivityAdmin> createState() => _ActivityAdminState();
}

class _ActivityAdminState extends State<ActivityAdmin> {
  final _who = TextEditingController();
  String? _action;
  DateTimeRange? _range;
  Timer? _debounce;
  Timer? _refresh;
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
    // The log is a live view of the system, so keep it current without the person pressing anything.
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refresh?.cancel();
    _who.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _key = UniqueKey());
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Map<String, dynamic> get _query => {
        if (_who.text.trim().isNotEmpty) 'who': _who.text.trim(),
        if (_action != null) 'action': _action,
        if (_range != null) 'from': ymd(_range!.start),
        if (_range != null) 'to': ymd(_range!.end),
        'take': '100',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity'), actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ]),
      body: PageBody(onRefresh: () async => _reload(), children: [
        Fetch<Map<String, dynamic>>(
          key: ValueKey('summary$_key'),
          load: () async => asMap(await Api.instance.get('/audit/summary')),
          builder: (context, s, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _Stat('${s['entriesToday']}', 'things happened\ntoday', dark: true),
              _Stat('${s['signedInToday']} of ${s['peopleActive']}', 'people signed in\ntoday'),
              _Stat('${s['lockoutsThisWeek']}', 'lockouts\nthis week', alarming: (s['lockoutsThisWeek'] as int) > 0),
            ]),
            gap8,
            Text('${s['entriesThisWeek']} entries in the last 7 days', style: const TextStyle(fontSize: 13)),
            if ((s['topActions'] as List).isNotEmpty) ...[
              gap8,
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in asList(s['topActions']))
                  ActionChip(
                    label: Text('${a['label']} · ${a['count']}', style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() {
                      _action = _action == a['action'] ? null : a['action'] as String;
                      _key = UniqueKey();
                    }),
                    backgroundColor: _action == a['action'] ? C.ink : null,
                    labelStyle: TextStyle(color: _action == a['action'] ? Colors.white : C.ink),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        SectionTitle(
          'Everything that happened',
          trailing: (_action != null || _range != null || _who.text.isNotEmpty)
              ? TextButton(
                  onPressed: () => setState(() {
                    _action = null;
                    _range = null;
                    _who.clear();
                    _key = UniqueKey();
                  }),
                  child: const Text('Clear filters'),
                )
              : null,
        ),
        TextField(
          controller: _who,
          onChanged: _onSearch,
          decoration: inputDeco('Search by name, email or code', suffix: const Icon(Icons.search)),
        ),
        gap8,
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(_range == null ? 'Any date' : dayRange(ymd(_range!.start), ymd(_range!.end))),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2026),
                  lastDate: DateTime.now(),
                  initialDateRange: _range,
                );
                if (picked != null) {
                  setState(() {
                    _range = picked;
                    _key = UniqueKey();
                  });
                }
              },
            ),
          ),
        ]),
        gap12,
        Fetch<Map<String, dynamic>>(
          key: ValueKey('list$_key${_action ?? ''}${_range?.start}${_who.text}'),
          load: () async => asMap(await Api.instance.get('/audit', _query)),
          builder: (context, data, _) {
            final rows = asList(data['items']);
            if (rows.isEmpty) return const Panel(child: Text('Nothing matches those filters.'));
            return Column(children: [
              for (final r in rows) _Entry(r),
              if (data['nextCursor'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Showing the newest ${rows.length}. Narrow the filters to see older entries.',
                      style: const TextStyle(fontSize: 12, color: C.ink)),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.dark = false, this.alarming = false});
  final String value;
  final String label;
  final bool dark;
  final bool alarming;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Panel(
            color: dark ? C.ink : C.grey,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: display(22, color: dark ? Colors.white : (alarming ? C.red : C.ink))),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: dark ? Colors.white : C.ink)),
            ]),
          ),
        ),
      );
}

/// One line of the log. Tapping it shows the raw details behind the entry.
class _Entry extends StatelessWidget {
  const _Entry(this.row);
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final actor = row['actor'] as Map?;
    final who = actor?['fullName'] as String? ?? 'The system';
    final at = DateTime.parse('${row['at']}').toLocal();
    final meta = row['meta'];
    final hasDetail = meta != null || row['entityId'] != null;
    final locked = '${row['action']}'.contains('locked');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '  '),
                TextSpan(
                  text: '${row['label']}',
                  style: TextStyle(color: locked ? C.red : C.ink, fontWeight: locked ? FontWeight.w700 : FontWeight.w400),
                ),
                if (row['entity'] != 'Employee') TextSpan(text: '  ${row['entity']}', style: const TextStyle(fontSize: 12)),
              ])),
              const SizedBox(height: 2),
              Text(
                '${DateFormat('EEE d MMM, HH:mm').format(at)}${actor?['email'] == null ? '' : ' · ${actor!['email']}'}',
                style: const TextStyle(fontSize: 12),
              ),
            ]),
          ),
          if (hasDetail)
            IconButton(
              iconSize: 18,
              tooltip: 'Details',
              icon: const Icon(Icons.more_horiz),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('${row['label']} · ${row['entity']}'),
                  content: SingleChildScrollView(
                    child: SelectableText([
                      '$who${actor?['email'] == null ? '' : ' (${actor!['email']})'}',
                      DateFormat('EEE d MMM yyyy, HH:mm:ss').format(at),
                      if (row['entityId'] != null) 'Record: ${row['entityId']}',
                      if (meta != null) '\n$meta',
                    ].join('\n')),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
