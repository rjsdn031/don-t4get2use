import 'dart:io';

import 'package:dio/dio.dart';

import '../models/gifticon_models.dart';
import '../services/app_logger.dart';

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
          await AppLogger.log(
            tag: 'HTTP',
            event: 'retry_wait',
            data: {
              'delaySeconds': delay.inSeconds,
              'attempt': attempt + 1,
            },
          );
          await Future<void>.delayed(delay);
        }

        await AppLogger.log(
          tag: 'HTTP',
          event: 'parse_request',
          data: {
            'url': '${_dio.options.baseUrl}/api/gifticons/parse',
            'attempt': '${attempt + 1}/${retryDelays.length}',
            'rawTextLength': rawText.length,
          },
        );

        final result = await requestOnce();

        await AppLogger.log(
          tag: 'HTTP',
          event: 'parse_success',
          data: {
            'attempt': attempt + 1,
            'merchantName': result.merchantName,
            'itemName': result.itemName,
            'couponNumber': result.couponNumber,
            'expiresAt': result.expiresAt?.toIso8601String(),
          },
        );

        return result;
      } on DioException catch (e, st) {
        await AppLogger.log(
          tag: 'HTTP',
          event: 'dio_error',
          data: {
            'type': e.type.name,
            'message': e.message,
            'status': e.response?.statusCode,
            'response': '${e.response?.data}',
            'error': '${e.error}',
            'stack': '$st',
          },
        );

        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown ||
            e.error is SocketException ||
            e.error is HttpException;

        final isLastAttempt = attempt == retryDelays.length - 1;
        if (!retryable || isLastAttempt) {
          await AppLogger.log(
            tag: 'HTTP',
            event: 'parse_failed_permanently',
            data: {
              'retryable': retryable,
              'attempt': attempt + 1,
            },
          );
          rethrow;
        }
      } catch (e, st) {
        await AppLogger.log(
          tag: 'HTTP',
          event: 'error',
          data: {
            'error': '$e',
            'stack': '$st',
          },
        );

        final retryable = e is SocketException || e is HttpException;
        final isLastAttempt = attempt == retryDelays.length - 1;
        if (!retryable || isLastAttempt) {
          await AppLogger.log(
            tag: 'HTTP',
            event: 'parse_failed_permanently',
            data: {
              'retryable': retryable,
              'attempt': attempt + 1,
            },
          );
          rethrow;
        }
      }
    }

    throw Exception('기프티콘 파싱 요청에 실패했습니다.');
  }
}