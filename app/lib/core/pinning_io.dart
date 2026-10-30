import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'config.dart';

/// Android/iOS: when the server uses a self-signed certificate, accept it only if its
/// SHA-256 fingerprint matches the one built into the app. Normal validation still runs first.
void configurePinning(Dio dio) {
  final pin = AppConfig.serverCertSha256.replaceAll(':', '').toLowerCase();
  if (pin.isEmpty) return;
  dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => sha256.convert(cert.der).toString() == pin;
    return client;
  });
}
