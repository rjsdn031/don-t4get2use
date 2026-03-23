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

  GifticonDetectionResult detect(
      OcrResult ocr,
      BarcodeDetectionResult barcode,
      ) {
    final normalized = _normalize(ocr.rawText);
    double score = 0;
    final matchedSignals = <String>[];

    int matchedKeywordCount = 0;
    for (final keyword in _signalKeywords) {
      if (normalized.contains(_normalize(keyword))) {
        matchedKeywordCount += 1;
        score += 0.9;
        matchedSignals.add('keyword:$keyword');
      }
    }

    final hasDate = _containsDate(normalized);
    if (hasDate) {
      score += 1.2;
      matchedSignals.add('date');
    }

    final hasCouponNumberLike = _containsBarcodeLikeNumber(normalized);
    if (hasCouponNumberLike) {
      score += 0.8;
      matchedSignals.add('coupon_number_like');
    }

    if (barcode.hasBarcodeLike) {
      score += 2.2;
      matchedSignals.add('barcode_detected');
    }

    if (barcode.hasQrLike) {
      score += 2.0;
      matchedSignals.add('qr_detected');
    }

    if (barcode.rawValues.isNotEmpty) {
      score += 0.8;
      matchedSignals.add('barcode_raw_value');
    }

    final hasStrongCodeSignal = barcode.hasStrongCodeSignal;
    final hasStrongTextSignal =
        hasDate && hasCouponNumberLike && matchedKeywordCount >= 1;

    // 코드 신호가 전혀 없으면 강하게 감점
    if (!hasStrongCodeSignal) {
      score -= 1.8;
      matchedSignals.add('penalty:no_barcode_or_qr');
    }

    // 코드 신호가 있고, 날짜나 쿠폰번호/키워드가 붙으면 추가 가점
    if (hasStrongCodeSignal && (hasDate || hasCouponNumberLike || matchedKeywordCount >= 1)) {
      score += 0.7;
      matchedSignals.add('code_plus_coupon_context');
    }

    final isGifticon =
    hasStrongCodeSignal
        ? score >= 2.8
        : hasStrongTextSignal && score >= 3.2;

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