import 'package:geolocator/geolocator.dart';

class GeoReading {
  const GeoReading(this.latitude, this.longitude, this.accuracyM);
  final double latitude;
  final double longitude;
  final double accuracyM;
}

// Matches the server: a fix less precise than this can't place someone inside an office.
const _maxAccuracyM = 200.0;

/// Reads the device position (phones and browsers). Returns null when location is off,
/// not allowed, or takes too long.
Future<GeoReading?> readPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return GeoReading(p.latitude, p.longitude, p.accuracy);
  } catch (_) {
    return null;
  }
}

/// True when the position is inside one of the office radiuses the server listed.
bool atOfficeLocation(GeoReading? g, List<dynamic> networks) {
  if (g == null || g.accuracyM > _maxAccuracyM) return false;
  for (final n in networks) {
    final m = (n as Map).cast<String, dynamic>();
    final lat = (m['latitude'] as num?)?.toDouble();
    final lon = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) continue;
    final radius = (m['radiusM'] as num?)?.toDouble() ?? 150;
    if (Geolocator.distanceBetween(g.latitude, g.longitude, lat, lon) <= radius) return true;
  }
  return false;
}
