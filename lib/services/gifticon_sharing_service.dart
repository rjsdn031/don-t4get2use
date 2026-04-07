import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/stored_gifticon.dart';
import 'app_logger.dart';
import 'device_id_service.dart';
import 'gifticon_storage_service.dart';

class GifticonSharingService {
  GifticonSharingService({
    required String baseUrl,
    required this.storageService,
    required this.deviceIdService,
    Dio? dio,
  }) : _dio = dio ??
      Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ),
      );

  final Dio _dio;
  final GifticonStorageService storageService;
  final DeviceIdService deviceIdService;

  Future<void> uploadForSharing(StoredGifticon stored) async {
    try {
      if (stored.sharedAt != null) {
        await AppLogger.log(
          tag: 'Sharing',
          event: 'upload_skip_already_shared',
          data: {
            'gifticonId': stored.id,
          },
        );
        return;
      }

      await AppLogger.log(
        tag: 'Sharing',
        event: 'upload_start',
        data: {
          'gifticonId': stored.id,
          'merchantName': stored.merchantName,
          'itemName': stored.itemName,
          'couponNumber': stored.couponNumber,
          'expiresAt': stored.expiresAt?.toIso8601String(),
        },
      );

      final deviceId = await deviceIdService.getDeviceId();
      final imageBase64 = await _readImageAsBase64(stored.imagePath);

      if (imageBase64 == null) {
        await AppLogger.log(
          tag: 'Sharing',
          event: 'upload_skip_image_encode_failed',
          data: {
            'gifticonId': stored.id,
          },
        );
        return;
      }

      await _dio.post<void>(
        '/api/gifticons/share',
        data: {
          'gifticonId': stored.id,
          'ownerId': deviceId,
          'imageBase64': imageBase64,
          'merchantName': stored.merchantName,
          'itemName': stored.itemName,
          'couponNumber': stored.couponNumber,
          'expiresAt': stored.expiresAt?.toIso8601String(),
        },
      );

      await storageService.markAsShared(stored.id);

      await AppLogger.log(
        tag: 'Sharing',
        event: 'upload_success',
        data: {
          'gifticonId': stored.id,
          'ownerId': deviceId,
        },
      );
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'upload_failed',
        data: {
          'gifticonId': stored.id,
          'error': '$e',
          'stack': '$st',
        },
      );
    }
  }

  Future<void> markAsUsedRemote({
    required String gifticonId,
  }) async {
    try {
      final deviceId = await deviceIdService.getDeviceId();

      await AppLogger.log(
        tag: 'Sharing',
        event: 'mark_used_remote_start',
        data: {
          'gifticonId': gifticonId,
          'usedBy': deviceId,
        },
      );

      await _dio.post<void>(
        '/api/gifticons/used',
        data: {
          'gifticonId': gifticonId,
          'usedBy': deviceId,
        },
      );

      await AppLogger.log(
        tag: 'Sharing',
        event: 'mark_used_remote_success',
        data: {
          'gifticonId': gifticonId,
          'usedBy': deviceId,
        },
      );
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'mark_used_remote_failed',
        data: {
          'gifticonId': gifticonId,
          'error': '$e',
          'stack': '$st',
        },
      );
    }
  }

  Future<StoredGifticon?> receiveSharedGifticon({
    required String gifticonId,
    required String imageUrl,
    required String ownerId,
    String? ownerNickname,
    required String? merchantName,
    required String? itemName,
    required String? couponNumber,
    required DateTime expiresAt,
  }) async {
    try {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'receive_start',
        data: {
          'gifticonId': gifticonId,
          'imageUrl': imageUrl,
          'ownerId': ownerId,
          'ownerNickname': ownerNickname,
          'merchantName': merchantName,
          'itemName': itemName,
          'couponNumber': couponNumber,
          'expiresAt': expiresAt.toIso8601String(),
        },
      );

      final localPath = await _downloadImageFromStorage(
        imageUrl: imageUrl,
        gifticonId: gifticonId,
      );

      if (localPath == null) {
        await AppLogger.log(
          tag: 'Sharing',
          event: 'receive_skip_download_failed',
          data: {
            'gifticonId': gifticonId,
          },
        );
        return null;
      }

      final stored = await storageService.saveReceivedGifticon(
        gifticonId: gifticonId,
        localImagePath: localPath,
        merchantName: merchantName,
        itemName: itemName,
        couponNumber: couponNumber,
        expiresAt: expiresAt,
        receivedFrom: ownerId,
        ownerNickname: ownerNickname,
      );

      await AppLogger.log(
        tag: 'Sharing',
        event: 'receive_success',
        data: {
          'gifticonId': gifticonId,
          'ownerNickname': ownerNickname,
          'localPath': localPath,
        },
      );

      return stored;
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'receive_failed',
        data: {
          'gifticonId': gifticonId,
          'error': '$e',
          'stack': '$st',
        },
      );
      return null;
    }
  }

  Future<String?> _readImageAsBase64(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        await AppLogger.log(
          tag: 'Sharing',
          event: 'image_file_missing',
          data: {
            'localPath': localPath,
          },
        );
        return null;
      }

      final bytes = await file.readAsBytes();

      await AppLogger.log(
        tag: 'Sharing',
        event: 'image_base64_encoded',
        data: {
          'localPath': localPath,
          'byteLength': bytes.length,
        },
      );

      return base64Encode(bytes);
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'image_base64_encode_failed',
        data: {
          'localPath': localPath,
          'error': '$e',
          'stack': '$st',
        },
      );
      return null;
    }
  }

  Future<String?> _downloadImageFromStorage({
    required String imageUrl,
    required String gifticonId,
  }) async {
    try {
      final tempDir = Directory.systemTemp;
      final localFile = File('${tempDir.path}/gifticon_received_$gifticonId.jpg');

      await AppLogger.log(
        tag: 'Sharing',
        event: 'download_start',
        data: {
          'gifticonId': gifticonId,
          'imageUrl': imageUrl,
          'localPath': localFile.path,
        },
      );

      final response = await _dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data;
      if (bytes == null) {
        await AppLogger.log(
          tag: 'Sharing',
          event: 'download_empty_response',
          data: {
            'gifticonId': gifticonId,
            'imageUrl': imageUrl,
          },
        );
        return null;
      }

      await localFile.writeAsBytes(bytes, flush: true);

      await AppLogger.log(
        tag: 'Sharing',
        event: 'download_success',
        data: {
          'gifticonId': gifticonId,
          'localPath': localFile.path,
          'byteLength': bytes.length,
        },
      );

      return localFile.path;
    } catch (e, st) {
      await AppLogger.log(
        tag: 'Sharing',
        event: 'download_failed',
        data: {
          'gifticonId': gifticonId,
          'imageUrl': imageUrl,
          'error': '$e',
          'stack': '$st',
        },
      );
      return null;
    }
  }
}