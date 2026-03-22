import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';

class RemoteGifticonAiParser {
  final Dio _dio;

  RemoteGifticonAiParser({
    required String baseUrl,
  }) : _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  Future<GifticonInfo> parse({
    required String rawText,
  }) async {
    try {
      debugPrint('[Gifticon][HTTP] POST ${_dio.options.baseUrl}/api/gifticons/parse');
      debugPrint('[Gifticon][HTTP][Request] rawText length=${rawText.length}');

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/gifticons/parse',
        data: {
          'rawText': rawText,
        },
      );

      debugPrint('[Gifticon][HTTP][Status] ${response.statusCode}');
      debugPrint('[Gifticon][HTTP][Data] ${response.data}');

      final data = response.data;
      if (data == null) {
        throw Exception('응답 데이터가 비어 있습니다.');
      }

      return GifticonInfo.fromJson(
        data,
        rawText: rawText,
      );
    } on DioException catch (e) {
      debugPrint('[Gifticon][HTTP][DioError] type=${e.type}');
      debugPrint('[Gifticon][HTTP][DioError] message=${e.message}');
      debugPrint('[Gifticon][HTTP][DioError] status=${e.response?.statusCode}');
      debugPrint('[Gifticon][HTTP][DioError] response=${e.response?.data}');
      rethrow;
    } catch (e) {
      debugPrint('[Gifticon][HTTP][UnknownError] $e');
      rethrow;
    }
  }
}