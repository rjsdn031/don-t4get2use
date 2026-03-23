import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';

class RemoteGifticonAiParser {
  RemoteGifticonAiParser({
    required String baseUrl,
  }) : _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Connection': 'close',
      },
    ),
  );

  final Dio _dio;

  Future<GifticonInfo> parse({
    required String rawText,
  }) async {
    Future<GifticonInfo> requestOnce() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/gifticons/parse',
        data: {
          'rawText': rawText,
        },
      );

      final data = response.data;
      if (data == null) {
        throw Exception('응답 데이터가 비어 있습니다.');
      }

      return GifticonInfo.fromJson(
        data,
        rawText: rawText,
      );
    }

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];

    for (int attempt = 0; attempt < retryDelays.length; attempt++) {
      try {
        final delay = retryDelays[attempt];
        if (delay > Duration.zero) {
          debugPrint(
            '[Gifticon][HTTP] waiting ${delay.inSeconds}s before retry...',
          );
          await Future<void>.delayed(delay);
        }

        debugPrint(
          '[Gifticon][HTTP] POST ${_dio.options.baseUrl}/api/gifticons/parse',
        );
        debugPrint(
          '[Gifticon][HTTP][Attempt] ${attempt + 1}/${retryDelays.length}',
        );
        debugPrint('[Gifticon][HTTP][Request] rawText length=${rawText.length}');

        final result = await requestOnce();
        debugPrint('[Gifticon][HTTP] parse success');
        return result;
      } on DioException catch (e, st) {
        debugPrint('[Gifticon][HTTP][DioError] type=${e.type}');
        debugPrint('[Gifticon][HTTP][DioError] message=${e.message}');
        debugPrint('[Gifticon][HTTP][DioError] status=${e.response?.statusCode}');
        debugPrint('[Gifticon][HTTP][DioError] response=${e.response?.data}');
        debugPrint('[Gifticon][HTTP][DioError] error=${e.error}');
        debugPrintStack(stackTrace: st);

        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown ||
            e.error is SocketException ||
            e.error is HttpException;

        final isLastAttempt = attempt == retryDelays.length - 1;
        if (!retryable || isLastAttempt) {
          debugPrint(
            '[Gifticon][HTTP] parse failed permanently '
                '(retryable=$retryable, attempt=${attempt + 1})',
          );
          rethrow;
        }
      } catch (e, st) {
        debugPrint('[Gifticon][HTTP][Error] $e');
        debugPrintStack(stackTrace: st);

        final retryable = e is SocketException || e is HttpException;
        final isLastAttempt = attempt == retryDelays.length - 1;
        if (!retryable || isLastAttempt) {
          debugPrint(
            '[Gifticon][HTTP] parse failed permanently '
                '(retryable=$retryable, attempt=${attempt + 1})',
          );
          rethrow;
        }
      }
    }

    throw Exception('기프티콘 파싱 요청에 실패했습니다.');
  }
}