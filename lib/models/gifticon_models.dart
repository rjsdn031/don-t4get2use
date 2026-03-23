import 'dart:convert';

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

  factory GifticonInfo.fromJson(
      Map<String, dynamic> json, {
        required String rawText,
      }) {
    return GifticonInfo(
      merchantName: json['merchantName'] as String?,
      itemName: json['itemName'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      couponNumber: json['couponNumber'] as String?,
      rawText: rawText,
    );
  }

  Map<String, dynamic> toJson() => {
    'merchantName': merchantName,
    'itemName': itemName,
    'expiresAt': expiresAt?.toIso8601String(),
    'couponNumber': couponNumber,
    'rawText': rawText,
  };
}