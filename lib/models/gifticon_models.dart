import 'dart:convert';

class PickedImageData {
  final String path;
  final String fileName;
  final int sizeBytes;

  const PickedImageData({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });
}

class OcrResult {
  final String rawText;
  final List<String> lines;

  const OcrResult({
    required this.rawText,
    required this.lines,
  });
}

class GifticonDetectionResult {
  final bool isGifticon;
  final double score;
  final List<String> matchedSignals;
  final OcrResult ocr;

  const GifticonDetectionResult({
    required this.isGifticon,
    required this.score,
    required this.matchedSignals,
    required this.ocr,
  });
}

class GifticonInfo {
  final String? merchantName;
  final String? itemName;
  final DateTime? expiresAt;
  final String? couponNumber;
  final String rawText;

  const GifticonInfo({
    required this.merchantName,
    required this.itemName,
    required this.expiresAt,
    required this.couponNumber,
    required this.rawText,
  });

  Map<String, dynamic> toJson() => {
    'merchantName': merchantName,
    'itemName': itemName,
    'expiresAt': expiresAt?.toIso8601String(),
    'couponNumber': couponNumber,
    'rawText': rawText,
  };

  @override
  String toString() => jsonEncode(toJson());
}

class GifticonSavePayload {
  final String ownerUserId;
  final String imagePath;
  final GifticonInfo info;

  const GifticonSavePayload({
    required this.ownerUserId,
    required this.imagePath,
    required this.info,
  });
}

class GifticonSaveResponse {
  final String id;
  final String imageUrl;

  const GifticonSaveResponse({
    required this.id,
    required this.imageUrl,
  });

  factory GifticonSaveResponse.fromJson(Map<String, dynamic> json) {
    return GifticonSaveResponse(
      id: json['id'] as String,
      imageUrl: json['imageUrl'] as String,
    );
  }
}