import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Kitchen view: veg / non-veg counts for a day, and setting the menu.
class CafeteriaAdmin extends StatefulWidget {
  const CafeteriaAdmin({super.key});

  @override
  State<CafeteriaAdmin> createState() => _CafeteriaAdminState();
}

class _CafeteriaAdminState extends State<CafeteriaAdmin> {
  DateTime _date = DateTime.now();
  String? _locationId = (Session.instance.me?['location'] as Map?)?['id'] as String?;
  final _veg = TextEditingController();
  final _nonVeg = TextEditingController();

  Future<void> _saveMenu() async {
    if (_locationId == null) {
      showSnack(context, 'Pick a location first');
      return;
    }
    await attempt(
      context,
      () => Api.instance.put('/meals/menu/${ymd(_date)}', {'locationId': _locationId, 'vegMenu': _veg.text.trim(), 'nonVegMenu': _nonVeg.text.trim()}),
      success: 'Menu saved',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = ymd(_date);
    return Scaffold(
      appBar: AppBar(title: const Text('Cafeteria'), actions: [
        TextButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(niceDay(d)),
          onPressed: () async {
            final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 30)));
            if (p != null) setState(() => _date = p);
          },
        ),
      ]),
      body: Fetch<List<Map<String, dynamic>>>(
        load: () async => asList((await Api.instance.get('/lookups'))['locations']),
        builder: (context, locations, _) => PageBody(maxWidth: 640, children: [
          DropdownButtonFormField<String?>(
            value: _locationId,
            decoration: inputDeco('Location'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All locations')),
              for (final l in locations) DropdownMenuItem(value: l['id'] as String, child: Text('${l['name']}')),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          gap16,
          Fetch<Map<String, dynamic>>(
            key: ValueKey('$d$_locationId'),
            load: () async => asMap(await Api.instance.get('/meals/counts', {'date': d, if (_locationId != null) 'locationId': _locationId})),
            builder: (context, c, reload) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Panel(
                color: C.ink,
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c['total']}', style: display(44, color: Colors.white)),
                      const Text('lunches to cook', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  IconButton(onPressed: reload, icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'Refresh'),
                ]),
              ),
              gap8,
              Row(children: [
                Expanded(child: _Count(veg: true, n: c['veg'] as int)),
                const SizedBox(width: 8),
                Expanded(child: _Count(veg: false, n: c['nonVeg'] as int)),
              ]),
              gap8,
              Text('${c['none']} in office but skipping lunch', style: const TextStyle(fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Who ordered'),
          Fetch<List<Map<String, dynamic>>>(
            key: ValueKey('who$d$_locationId'),
            load: () async => asList(await Api.instance.get('/meals/bookings', {'date': d, if (_locationId != null) 'locationId': _locationId})),
            builder: (context, rows, _) => rows.isEmpty
                ? const Panel(child: Text('Nobody has ordered lunch for this day yet.'))
                : Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          leading: FoodMark(veg: r['choice'] == 'VEG'),
                          title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([r['code'], r['department']].whereType<String>().join(' · ')),
                          trailing: Text(r['choice'] == 'VEG' ? 'Veg' : 'Non-veg'),
                        ),
                    ]),
                  ),
          ),
          const SizedBox(height: 24),
          SectionTitle('Menu for ${niceDay(d)}'),
          TextField(controller: _veg, decoration: inputDeco('Veg menu').copyWith(prefixIcon: const Padding(padding: EdgeInsets.all(14), child: FoodMark(veg: true)))),
          gap12,
          TextField(controller: _nonVeg, decoration: inputDeco('Non-veg menu').copyWith(prefixIcon: const Padding(padding: EdgeInsets.all(14), child: FoodMark(veg: false)))),
          gap12,
          FilledButton(onPressed: _saveMenu, child: const Text('Save menu')),
        ]),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.veg, required this.n});
  final bool veg;
  final int n;

  @override
  Widget build(BuildContext context) => Panel(
        child: Row(children: [
          FoodMark(veg: veg, size: 22),
          const SizedBox(width: 12),
          Text('$n', style: display(28)),
          const SizedBox(width: 8),
          Text(veg ? 'Veg' : 'Non-veg', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
