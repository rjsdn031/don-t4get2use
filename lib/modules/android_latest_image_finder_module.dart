import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_image_data.dart';
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

      debugPrint('[Gifticon][LatestImage] raw result: $result');

      if (result == null) {
        debugPrint('[Gifticon][LatestImage] result is null');
        return null;
      }

      final debugLogs = result['debugLogs'];
      if (debugLogs is List) {
        for (final log in debugLogs) {
          debugPrint('[Gifticon][LatestImage][Native] $log');
        }
      }

      final path = result['path'] as String?;
      final fileName = result['fileName'] as String?;
      final sizeBytes = result['sizeBytes'] as int?;

      debugPrint('[Gifticon][LatestImage] path=$path');
      debugPrint('[Gifticon][LatestImage] fileName=$fileName');
      debugPrint('[Gifticon][LatestImage] sizeBytes=$sizeBytes');

      if (path == null || path.isEmpty) {
        debugPrint('[Gifticon][LatestImage] path is null or empty');
        return null;
      }

      return LocalImageData(
        path: path,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
    } on PlatformException catch (e) {
      debugPrint('[Gifticon][LatestImage][PlatformException] ${e.code}: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[Gifticon][LatestImage][Error] $e');
      return null;
    }
  }
}