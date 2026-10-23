import 'package:dio/dio.dart';

import 'config.dart';
import 'session.dart';

class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Thin wrapper around Dio: adds the sign-in token and turns server errors into readable messages.
class Api {
  Api._() {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = Session.instance.token;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  static final instance = Api._();
  late final Dio dio;

  Future<dynamic> _wrap(Future<Response<dynamic>> call) async {
    try {
      final res = await call;
      return res.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final isAuthCall = e.requestOptions.path.startsWith('/auth/');
      if (status == 401 && !isAuthCall && Session.instance.token != null) {
        await Session.instance.logout();
      }
      final data = e.response?.data;
      var message = 'Something went wrong. Please try again.';
      if (data is Map && data['message'] != null) {
        final m = data['message'];
        message = m is List ? m.join(', ') : '$m';
      } else if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        message = "Can't reach the Sirena HR server. Check your connection.";
      }
      throw ApiError(message, status);
    }
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _wrap(dio.get(path, queryParameters: query));
  Future<dynamic> post(String path, [Object? body]) => _wrap(dio.post(path, data: body ?? {}));
  Future<dynamic> put(String path, [Object? body]) => _wrap(dio.put(path, data: body ?? {}));
  Future<dynamic> patch(String path, [Object? body]) => _wrap(dio.patch(path, data: body ?? {}));
  Future<dynamic> delete(String path) => _wrap(dio.delete(path));

  Future<dynamic> upload(String path, String filename, List<int> bytes) => _wrap(dio.post(
        path,
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
      ));
}

/// Casting helpers for JSON.
Map<String, dynamic> asMap(dynamic v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> asList(dynamic v) => (v as List).map((e) => asMap(e)).toList();
