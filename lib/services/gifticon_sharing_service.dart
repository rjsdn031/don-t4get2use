import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/stored_gifticon.dart';
import 'device_id_service.dart';
import 'gifticon_storage_service.dart';

class GifticonSharingService {
  GifticonSharingService({
    required String baseUrl,
    required this.storageService,
    required this.deviceIdService,
  }) : _dio = Dio(
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

  /// 만료 1일 전 호출 — Storage 업로드 + 서버에 공유 등록
  Future<void> uploadForSharing(StoredGifticon stored) async {
    try {
      if (stored.sharedAt != null) {
        debugPrint('[Sharing] already shared: id=${stored.id}');
        return;
      }

      final deviceId = await deviceIdService.getDeviceId();

      // 1. Firebase Storage에 이미지 업로드
      final imageUrl = await _uploadImageToStorage(
        localPath: stored.imagePath,
        gifticonId: stored.id,
      );

      if (imageUrl == null) {
        debugPrint('[Sharing] image upload failed: id=${stored.id}');
        return;
      }

      // 2. 서버에 공유 등록
      await _dio.post<void>(
        '/api/gifticons/share',
        data: {
          'gifticonId': stored.id,
          'ownerId': deviceId,
          'imageUrl': imageUrl,
          'merchantName': stored.merchantName,
          'itemName': stored.itemName,
          'couponNumber': stored.couponNumber,
          'expiresAt': stored.expiresAt?.toIso8601String(),
        },
      );

      // 3. 로컬 Hive에 sharedAt 업데이트
      await storageService.markAsShared(stored.id);

      debugPrint('[Sharing] uploaded for sharing: id=${stored.id}');
    } catch (e) {
      debugPrint('[Sharing] uploadForSharing failed: $e');
      // 실패해도 앱 동작에 영향 없음
    }
  }

  /// 사용함 처리 — 서버 Firestore + 상대방 FCM 동기화
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

  /// 공유받은 기프티콘을 로컬에 저장
  Future<StoredGifticon?> receiveSharedGifticon({
    required String gifticonId,
    required String imageUrl,
    required String ownerId,
    required String? merchantName,
    required String? itemName,
    required String? couponNumber,
    required DateTime expiresAt,
  }) async {
    try {
      // Storage에서 이미지 다운로드 → 로컬 저장
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
      );

      debugPrint('[Sharing] received gifticon saved: id=$gifticonId');
      return stored;
    } catch (e) {
      debugPrint('[Sharing] receiveSharedGifticon failed: $e');
      return null;
    }
  }

  Future<String?> _uploadImageToStorage({
    required String localPath,
    required String gifticonId,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[Sharing] image file not found: $localPath');
        return null;
      }

      final ref = FirebaseStorage.instance
          .ref()
          .child('gifticons/$gifticonId.jpg');

      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await task.ref.getDownloadURL();
      debugPrint('[Sharing] uploaded to storage: $url');
      return url;
    } catch (e) {
      debugPrint('[Sharing] storage upload failed: $e');
      return null;
    }
  }

  Future<String?> _downloadImageFromStorage({
    required String imageUrl,
    required String gifticonId,
  }) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(imageUrl);
      final tempDir = Directory.systemTemp;
      final localFile = File('${tempDir.path}/gifticon_received_$gifticonId.jpg');

      await ref.writeToFile(localFile);
      debugPrint('[Sharing] downloaded from storage: ${localFile.path}');
      return localFile.path;
    } catch (e) {
      debugPrint('[Sharing] storage download failed: $e');
      return null;
    }
  }
}