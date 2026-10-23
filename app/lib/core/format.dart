import 'package:intl/intl.dart';

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String todayYmd() => ymd(DateTime.now());
DateTime day(String s) => DateTime.parse(s.substring(0, 10));
String niceDay(String s) => DateFormat('EEE, d MMM').format(day(s));
String shortDay(String s) => DateFormat('d MMM').format(day(s));
String dayRange(String from, String to) => from == to ? niceDay(from) : '${shortDay(from)} – ${shortDay(to)}';
String clock(String iso) => DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());

/// 14.0 → "14", 14.5 → "14.5"
String num1(dynamic n) {
  final d = (n as num).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
}

String durationSince(String iso, [String? untilIso]) {
  final start = DateTime.parse(iso).toLocal();
  final end = untilIso != null ? DateTime.parse(untilIso).toLocal() : DateTime.now();
  final mins = end.difference(start).inMinutes.clamp(0, 24 * 60);
  return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
}

const leaveStatusLabel = {
  'PENDING_MANAGER': 'Waiting on manager',
  'PENDING_HR': 'Waiting on HR',
  'APPROVED': 'Approved',
  'REJECTED': 'Declined',
  'CANCELLED': 'Cancelled',
};

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// IN_PROGRESS → "In progress"
String prettyEnum(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');
