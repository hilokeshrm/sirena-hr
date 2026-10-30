import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'geo.dart';
import 'wifi.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map<String, dynamic>? _today;
  List<Map<String, dynamic>> _history = [];
  WifiReading? _wifi;
  GeoReading? _geo;
  bool _auto = !kIsWeb;
  String _place = 'OFFICE';
  bool _busy = false;
  String? _error;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.get('/attendance/today'),
        Api.instance.get('/attendance/me', {'from': ymd(DateTime.now().subtract(const Duration(days: 6))), 'to': todayYmd()}),
        readWifi(),
        readPosition(),
      ]);
      if (!mounted) return;
      setState(() {
        _today = asMap(r[0]);
        _history = asList(r[1]);
        _wifi = r[2] as WifiReading?;
        _geo = r[3] as GeoReading?;
        _error = null;
      });
      _tryAutoCheckIn();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<dynamic> get _networks => (_today?['officeNetworks'] as List?) ?? const [];
  bool get _onOfficeWifi => onOfficeWifi(_wifi, _networks);
  bool get _atOfficeLocation => atOfficeLocation(_geo, _networks);
  bool get _onOffice => _onOfficeWifi || _atOfficeLocation;
  Map<String, dynamic>? get _rec => (_today?['record'] as Map?)?.cast<String, dynamic>();

  /// Opening the app on office Wi-Fi, or at the office, checks you in by itself.
  Future<void> _tryAutoCheckIn() async {
    if (_autoTried || !_auto || _rec != null || _today?['onLeave'] == true || !_onOffice) return;
    _autoTried = true;
    await _checkIn(auto: true);
  }

  Future<void> _checkIn({bool auto = false}) async {
    setState(() => _busy = true);
    await attempt(
      context,
      () => Api.instance.post('/attendance/check-in', {
        'mode': auto ? 'OFFICE' : _place,
        'auto': auto,
        if (_wifi?.ssid != null) 'ssid': _wifi!.ssid,
        if (_wifi?.bssid != null) 'bssid': _wifi!.bssid,
        if (_geo != null) ...{'latitude': _geo!.latitude, 'longitude': _geo!.longitude, 'accuracyM': _geo!.accuracyM},
      }),
      success: !auto ? 'Checked in' : _onOfficeWifi ? 'Checked in on office Wi-Fi' : 'Checked in at the office',
    );
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    await attempt(context, () => Api.instance.post('/attendance/check-out', {}), success: 'Checked out');
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rec = _rec;
    final checkedOut = rec?['checkOutAt'] != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _today == null
              ? const Center(child: CircularProgressIndicator(color: C.red))
              : PageBody(onRefresh: _load, maxWidth: 640, children: [
                  if (!kIsWeb)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Auto (at office)')),
                        ButtonSegment(value: false, label: Text('Manual')),
                      ],
                      selected: {_auto},
                      onSelectionChanged: (v) => setState(() => _auto = v.first),
                    ),
                  gap16,
                  Panel(
                    padding: const EdgeInsets.all(22),
                    child: Column(children: [
                      Text(
                        _today!['onLeave'] == true
                            ? "You're on leave today"
                            : rec == null
                                ? 'Not checked in'
                                : checkedOut
                                    ? 'Checked out at ${clock(rec['checkOutAt'] as String)}'
                                    : 'Checked in at ${clock(rec['checkInAt'] as String)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      gap8,
                      Text(rec == null ? '0h 00m' : durationSince(rec['checkInAt'] as String, rec['checkOutAt'] as String?), style: display(52)),
                      if (rec != null)
                        Text(
                          '${rec['mode'] == 'WFH' ? 'Working from home' : 'Office'} · ${rec['method'] == 'WIFI' ? 'office Wi-Fi' : rec['method'] == 'GPS' ? 'office location' : 'manual'}${rec['flagged'] == true ? ' · flagged for HR (not at the office)' : ''}',
                          textAlign: TextAlign.center,
                        ),
                      gap16,
                      SizedBox(
                        width: double.infinity,
                        child: _today!['onLeave'] == true
                            ? const SizedBox.shrink()
                            : rec != null && !checkedOut
                                ? FilledButton(onPressed: _busy ? null : _checkOut, child: const Text('Check out'))
                                : FilledButton(
                                    onPressed: _busy ? null : () => _checkIn(auto: _auto && _onOffice),
                                    child: Text(rec == null ? 'Check in' : 'Check in again'),
                                  ),
                      ),
                    ]),
                  ),
                  gap12,
                  if (_auto && !kIsWeb)
                    Text(
                      _onOfficeWifi
                          ? "You're on ${_wifi?.ssid ?? 'office Wi-Fi'}. Check-in happens automatically when you open the app."
                          : _atOfficeLocation
                              ? "You're at the office. Check-in happens automatically when you open the app."
                              : "Not on office Wi-Fi or at the office${_wifi?.ssid != null ? ' (connected to ${_wifi!.ssid})' : ''}. "
                                  'Turn on location, or switch to Manual to check in from elsewhere.',
                    )
                  else ...[
                    const Text('Working from', style: TextStyle(fontWeight: FontWeight.w700)),
                    gap8,
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'OFFICE', label: Text('Office'), icon: Icon(Icons.apartment)),
                        ButtonSegment(value: 'WFH', label: Text('Home'), icon: Icon(Icons.home_outlined)),
                      ],
                      selected: {_place},
                      onSelectionChanged: (v) => setState(() => _place = v.first),
                    ),
                    gap8,
                    Text(_place == 'OFFICE'
                        ? 'Office check-ins from outside the office network are flagged for HR to confirm.'
                        : 'Counts as a WFH day. Lunch booking is turned off for today.'),
                  ],
                  gap16,
                  const SectionTitle('Last 7 days'),
                  if (_history.isEmpty) const EmptyView('No check-ins yet.'),
                  for (final h in _history.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(child: Text('${niceDay(h['date'] as String)} · ${h['mode'] == 'WFH' ? 'WFH' : 'Office'}')),
                        Text(
                          h['checkOutAt'] != null ? durationSince(h['checkInAt'] as String, h['checkOutAt'] as String) : 'in since ${clock(h['checkInAt'] as String)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ]),
                    ),
                ]),
    );
  }
}
