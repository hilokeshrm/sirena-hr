import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Fetch<Map<String, dynamic>>(
        load: () async => asMap(await Api.instance.get('/employees/$id')),
        builder: (context, e, reload) {
          final restricted = e['restricted'] == true;
          return PageBody(maxWidth: 640, onRefresh: reload, children: [
            Panel(
              color: C.ink,
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Avatar(e['fullName'] as String, size: 64, dark: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e['fullName']}', style: display(24, color: Colors.white)),
                    Text('${e['designation'] ?? ''}', style: const TextStyle(color: Colors.white)),
                    Text('${e['code']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            gap16,
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Email'),
                  onPressed: () => launchUrl(Uri(scheme: 'mailto', path: e['email'] as String)),
                ),
              ),
              if (restricted && e['phone'] != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: e['phone'] as String)),
                  ),
                ),
              ],
            ]),
            gap16,
            const SectionTitle('Work'),
            InfoRows({
              'Email': e['email'],
              'Department': (e['department'] as Map?)?['name'],
              'Location': (e['location'] as Map?)?['name'],
              'Reports to': (e['manager'] as Map?)?['fullName'],
              'Work mode': e['workMode'] == null ? null : prettyEnum(e['workMode'] as String),
              if (restricted) 'Joined': e['joinedOn'] == null ? null : niceDay(e['joinedOn'] as String),
              if (restricted) 'Employment': e['employmentType'] == null ? null : prettyEnum(e['employmentType'] as String),
            }),
            if (restricted) ...[
              gap16,
              const SectionTitle('Personal (HR only)'),
              InfoRows({
                'Phone': e['phone'],
                'Personal email': e['personalEmail'],
                'Date of birth': e['dateOfBirth'] == null ? null : niceDay(e['dateOfBirth'] as String),
                'Blood group': e['bloodGroup'],
                'Food': e['foodPref'] == null ? null : (e['foodPref'] == 'VEG' ? 'Veg' : 'Non-veg'),
                'Address': e['address'],
                'Emergency contact': e['emergencyName'] == null ? null : '${e['emergencyName']} (${e['emergencyRelation'] ?? ''}) ${e['emergencyPhone'] ?? ''}',
                'Qualification': e['qualification'],
                'Experience': e['experienceYears'] == null ? null : '${e['experienceYears']} yrs',
              }),
            ],
          ]);
        },
      ),
    );
  }
}

/// Label / value rows; empty values are skipped.
class InfoRows extends StatelessWidget {
  const InfoRows(this.rows, {super.key});
  final Map<String, dynamic> rows;

  @override
  Widget build(BuildContext context) {
    final shown = rows.entries.where((e) => e.value != null && '${e.value}'.isNotEmpty).toList();
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < shown.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: i == shown.length - 1 ? null : const Border(bottom: BorderSide(color: C.grey))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 140, child: Text(shown[i].key, style: const TextStyle(fontSize: 13))),
              Expanded(child: SelectableText('${shown[i].value}', style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
      ]),
    );
  }
}
