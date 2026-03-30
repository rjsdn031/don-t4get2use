import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/stored_gifticon.dart';
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
        debugPrint('[Sharing] already shared: id=${stored.id}');
        return;
      }

      final deviceId = await deviceIdService.getDeviceId();
      final imageBase64 = await _readImageAsBase64(stored.imagePath);

      if (imageBase64 == null) {
        debugPrint('[Sharing] image base64 encode failed: id=${stored.id}');
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
      debugPrint('[Sharing] uploaded for sharing: id=${stored.id}');
    } catch (e) {
      debugPrint('[Sharing] uploadForSharing failed: $e');
    }
  }

  Future<void> markAsUsedRemote({
    required String gifticonId,
  }) async {
    try {
      final deviceId = await deviceIdService.getDeviceId();

      await _dio.post<void>(
        '/api/gifticons/used',
        data: {
          'gifticonId': gifticonId,
          'usedBy': deviceId,
        },
      );

      debugPrint('[Sharing] markAsUsedRemote success: id=$gifticonId');
    } catch (e) {
      debugPrint('[Sharing] markAsUsedRemote failed: $e');
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
      final localPath = await _downloadImageFromStorage(
        imageUrl: imageUrl,
        gifticonId: gifticonId,
      );

      if (localPath == null) {
        debugPrint('[Sharing] image download failed: id=$gifticonId');
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

      debugPrint(
        '[Sharing] received gifticon saved: id=$gifticonId ownerNickname=$ownerNickname',
      );
      return stored;
    } catch (e) {
      debugPrint('[Sharing] receiveSharedGifticon failed: $e');
      return null;
    }
  }

  Future<String?> _readImageAsBase64(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[Sharing] image file not found: $localPath');
        return null;
      }

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('[Sharing] base64 encode failed: $e');
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

      final response = await _dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data;
      if (bytes == null) {
        debugPrint('[Sharing] download response empty');
        return null;
      }

      await localFile.writeAsBytes(bytes, flush: true);
      debugPrint('[Sharing] downloaded from url: ${localFile.path}');
      return localFile.path;
    } catch (e) {
      debugPrint('[Sharing] storage download failed: $e');
      return null;
    }
  }
}