import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key, required this.id});
  final String id;

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  Key _key = UniqueKey();
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Policy')),
      body: Fetch<Map<String, dynamic>>(
        key: _key,
        load: () async => asMap(await Api.instance.get('/policies/${widget.id}')),
        builder: (context, p, reload) {
          final acked = p['ackedAt'] != null;
          return PageBody(maxWidth: 720, children: [
            Text('${p['category']}'.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('${p['title']}', style: display(28)),
            Text('Version ${p['version']}${p['publishedAt'] != null ? ' · published ${niceDay(p['publishedAt'] as String)}' : ''}', style: const TextStyle(fontSize: 13)),
            if (p['changeSummary'] != null) ...[
              gap12,
              Panel(color: C.grey, child: Text('What changed: ${p['changeSummary']}', style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
            gap16,
            // Policy bodies are plain text / light markdown; shown as selectable text.
            SelectableText('${p['body']}', style: const TextStyle(fontSize: 15, height: 1.6)),
            const SizedBox(height: 28),
            if (p['requireAck'] == true)
              acked
                  ? Panel(
                      color: C.ink,
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 10),
                        Text('You acknowledged this on ${niceDay(p['ackedAt'] as String)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      CheckboxListTile(
                        value: _agree,
                        activeColor: C.red,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('I have read and understood this policy'),
                        onChanged: (v) => setState(() => _agree = v ?? false),
                      ),
                      gap8,
                      FilledButton(
                        onPressed: !_agree
                            ? null
                            : () async {
                                final r = await attempt(context, () => Api.instance.post('/policy-versions/${p['versionId']}/ack'), success: 'Thanks, noted');
                                if (r != null && mounted) setState(() => _key = UniqueKey());
                              },
                        child: const Text('Acknowledge'),
                      ),
                    ]),
          ]);
        },
      ),
    );
  }
}
