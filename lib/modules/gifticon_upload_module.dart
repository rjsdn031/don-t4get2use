import 'dart:io';
import 'package:dio/dio.dart';
import '../models/gifticon_models.dart';

class GifticonUploadModule {
  GifticonUploadModule({required String baseUrl, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;

  Future<GifticonSaveResponse> uploadGifticon(
      GifticonSavePayload payload,
      ) async {
    final fileName = payload.imagePath.split(Platform.pathSeparator).last;

    final formData = FormData.fromMap({
      'ownerUserId': payload.ownerUserId,
      'merchantName': payload.info.merchantName,
      'itemName': payload.info.itemName,
      'expiresAt': payload.info.expiresAt?.toIso8601String(),
      'couponNumber': payload.info.couponNumber,
      'rawText': payload.info.rawText,
      'image': await MultipartFile.fromFile(
        payload.imagePath,
        filename: fileName,
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/gifticons',
      data: formData,
    );

    final data = response.data;
    if (data == null) {
      throw Exception('서버 응답이 비어 있습니다.');
    }

    return GifticonSaveResponse.fromJson(data);
  }
}