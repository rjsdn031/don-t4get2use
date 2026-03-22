import '../models/gifticon_models.dart';

class GifticonDetectorModule {
  static const List<String> _signalKeywords = [
    '교환권',
    '쿠폰',
    '기프티콘',
    '유효기간',
    '바코드',
    '사용처',
    '교환처',
    '선물',
    '모바일',
    '상품권',
  ];

  GifticonDetectionResult detect(OcrResult ocr) {
    final normalized = _normalize(ocr.rawText);
    double score = 0;
    final matchedSignals = <String>[];

    for (final keyword in _signalKeywords) {
      if (normalized.contains(_normalize(keyword))) {
        score += 1.2;
        matchedSignals.add('keyword:$keyword');
      }
    }

    if (_containsDate(normalized)) {
      score += 1.5;
      matchedSignals.add('date');
    }

    if (_containsBarcodeLikeNumber(normalized)) {
      score += 1.2;
      matchedSignals.add('barcode_like');
    }

    final isGifticon = score >= 2.5;

    return GifticonDetectionResult(
      isGifticon: isGifticon,
      score: score,
      matchedSignals: matchedSignals,
      ocr: ocr,
    );
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _containsDate(String text) {
    final patterns = [
      RegExp(r'20\d{2}[./-]\d{1,2}[./-]\d{1,2}'),
      RegExp(r'\d{4}년\d{1,2}월\d{1,2}일'),
    ];
    return patterns.any((p) => p.hasMatch(text));
  }

  bool _containsBarcodeLikeNumber(String text) {
    return RegExp(r'\d{8,}').hasMatch(text);
  }
}