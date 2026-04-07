import 'package:flutter/services.dart';

import '../models/local_image_data.dart';
import '../services/app_logger.dart';
import 'latest_image_finder_module.dart';

class AndroidLatestImageFinderModule implements LatestImageFinderModule {
  static const MethodChannel _channel =
  MethodChannel('gifticon/latest_image_finder');

  @override
  Future<LocalImageData?> findLatestImage() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
        'findLatestImage',
      );

      await AppLogger.log(
        tag: 'LatestImage',
        event: 'raw_result',
        data: {
          'resultIsNull': result == null,
        },
      );

      if (result == null) {
        await AppLogger.log(
          tag: 'LatestImage',
          event: 'result_null',
        );
        return null;
      }

      final debugLogs = result['debugLogs'];
      if (debugLogs is List) {
        for (final log in debugLogs) {
          await AppLogger.log(
            tag: 'LatestImage',
            event: 'native_log',
            data: {'message': '$log'},
          );
        }
      }

      final path = result['path'] as String?;
      final fileName = result['fileName'] as String?;
      final sizeBytes = result['sizeBytes'] as int?;

      await AppLogger.log(
        tag: 'LatestImage',
        event: 'parsed_result',
        data: {
          'path': path,
          'fileName': fileName,
          'sizeBytes': sizeBytes,
        },
      );

      if (path == null || path.isEmpty) {
        await AppLogger.log(
          tag: 'LatestImage',
          event: 'path_empty',
        );
        return null;
      }

      return LocalImageData(
        path: path,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
    } on PlatformException catch (e) {
      await AppLogger.log(
        tag: 'LatestImage',
        event: 'platform_exception',
        data: {
          'code': e.code,
          'message': e.message,
        },
      );
      return null;
    } catch (e) {
      await AppLogger.log(
        tag: 'LatestImage',
        event: 'error',
        data: {'error': '$e'},
      );
      return null;
    }
  }
}