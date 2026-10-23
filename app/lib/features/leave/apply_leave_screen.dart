import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ApplyLeaveScreen extends StatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  List<Map<String, dynamic>>? _types;
  String? _typeId;
  DateTimeRange? _range;
  String _half = 'NONE';
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  String? _previewError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/leave/balances').then((v) {
      if (!mounted) return;
      final types = asList(v);
      setState(() {
        _types = types;
        _typeId = types.firstWhere((t) => t['code'] == 'CL', orElse: () => types.first)['leaveTypeId'] as String;
      });
    });
  }

  Map<String, dynamic> get _body => {
        'leaveTypeId': _typeId,
        'fromDate': ymd(_range!.start),
        'toDate': ymd(_range!.end),
        'halfDay': _half,
        if (_reason.text.isNotEmpty) 'reason': _reason.text,
      };

  Future<void> _refreshPreview() async {
    if (_typeId == null || _range == null) return;
    try {
      final p = asMap(await Api.instance.post('/leave/preview', _body));
      if (mounted) setState(() => (_preview = p, _previewError = null));
    } on ApiError catch (e) {
      if (mounted) setState(() => (_preview = null, _previewError = e.message));
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (r == null) return;
    setState(() {
      _range = r;
      if (r.start != r.end) _half = 'NONE';
    });
    _refreshPreview();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await attempt(context, () => Api.instance.post('/leave/requests', _body), success: 'Request sent');
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final single = _range != null && _range!.start == _range!.end;
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: _types == null
          ? const Center(child: CircularProgressIndicator(color: C.red))
          : PageBody(maxWidth: 560, children: [
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w800)),
              gap8,
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _types!)
                  ChoiceChip(
                    showCheckmark: false,
                    selected: _typeId == t['leaveTypeId'],
                    label: Text('${t['name']}${t['unlimited'] == true ? '' : ' · ${num1(t['available'])}'}'),
                    onSelected: (_) {
                      setState(() => _typeId = t['leaveTypeId'] as String);
                      _refreshPreview();
                    },
                  ),
              ]),
              gap16,
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(_range == null ? 'Choose dates' : dayRange(ymd(_range!.start), ymd(_range!.end))),
                onPressed: _pickDates,
              ),
              if (single) ...[
                gap12,
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'NONE', label: Text('Full day')),
                    ButtonSegment(value: 'FIRST', label: Text('First half')),
                    ButtonSegment(value: 'SECOND', label: Text('Second half')),
                  ],
                  selected: {_half},
                  onSelectionChanged: (v) {
                    setState(() => _half = v.first);
                    _refreshPreview();
                  },
                ),
              ],
              gap16,
              if (_preview != null)
                Panel(
                  color: C.grey,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${num1(_preview!['days'])} working day${_preview!['days'] == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.red)),
                    TextSpan(text: ' · ${num1(_preview!['after'])} left after this'),
                  ])),
                ),
              if (_previewError != null) Text(_previewError!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
              gap16,
              TextField(controller: _reason, decoration: inputDeco('Reason (optional)'), maxLines: 3, minLines: 2),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy || _range == null || _preview == null ? null : _submit,
                child: const Text('Send request'),
              ),
              gap8,
              const Text('Goes to your manager first, then HR when needed.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            ]),
    );
  }
}
