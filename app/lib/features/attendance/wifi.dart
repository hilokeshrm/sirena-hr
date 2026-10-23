import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiReading {
  const WifiReading(this.ssid, this.bssid);
  final String? ssid;
  final String? bssid;
}

/// Reads the current Wi-Fi name and access point (phones only).
/// Android and iOS only reveal these with location permission; iOS also needs the
/// "Access WiFi Information" capability. Returns null on web or when not allowed.
Future<WifiReading?> readWifi() async {
  if (kIsWeb) return null;
  try {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return null;
    final info = NetworkInfo();
    final ssid = (await info.getWifiName())?.replaceAll('"', '');
    final bssid = await info.getWifiBSSID();
    if (ssid == null && bssid == null) return null;
    return WifiReading(ssid, bssid);
  } catch (_) {
    return null;
  }
}

/// True when the phone is on one of the office networks the server listed.
bool onOfficeWifi(WifiReading? w, List<dynamic> networks) {
  if (w == null) return false;
  final bssid = w.bssid?.toLowerCase();
  for (final n in networks) {
    final m = (n as Map).cast<String, dynamic>();
    final ids = (m['bssids'] as List).map((b) => '$b'.toLowerCase());
    if (bssid != null && ids.contains(bssid)) return true;
  }
  return false;
}
