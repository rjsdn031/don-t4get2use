import '../models/gifticon_models.dart';

class GifticonParserModule {
  GifticonInfo parse(OcrResult ocr) {
    final merchantName = _parseMerchantName(ocr.lines);
    final expiresAt = _parseExpiresAt(ocr.rawText, ocr.lines);
    final couponNumber = _parseCouponNumber(ocr.lines);
    final itemName = _parseItemName(
      lines: ocr.lines,
      merchantName: merchantName,
      couponNumber: couponNumber,
    );

    return GifticonInfo(
      merchantName: merchantName,
      itemName: itemName,
      expiresAt: expiresAt,
      couponNumber: couponNumber,
      rawText: ocr.rawText,
    );
  }

  String? _parseMerchantName(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = _clean(lines[i]);

      if (_containsMerchantLabel(line)) {
        final inlineValue = _extractValueAfterLabel(line);
        if (_isUseful(inlineValue)) return inlineValue;

        if (i + 1 < lines.length) {
          final next = _clean(lines[i + 1]);
          if (_isUseful(next)) return next;
        }
      }
    }

    final fallback = lines
        .map(_clean)
        .where((line) => _isUseful(line))
        .where((line) => !_containsExpiryLabel(line))
        .where((line) => !_containsItemLabel(line))
        .where((line) => !_looksLikeCouponNumber(line))
        .where((line) => _extractDate(line) == null)
        .where((line) => line.length >= 2 && line.length <= 20)
        .toList();

    return fallback.isEmpty ? null : fallback.first;
  }

  String? _parseItemName({
    required List<String> lines,
    required String? merchantName,
    required String? couponNumber,
  }) {
    for (int i = 0; i < lines.length; i++) {
      final line = _clean(lines[i]);

      if (_containsItemLabel(line)) {
        final inlineValue = _extractValueAfterLabel(line);
        if (_isUsefulItem(inlineValue, merchantName, couponNumber)) {
          return inlineValue;
        }

        if (i + 1 < lines.length) {
          final next = _clean(lines[i + 1]);
          if (_isUsefulItem(next, merchantName, couponNumber)) {
            return next;
          }
        }
      }
    }

    final candidates = lines
        .map(_clean)
        .where((line) => _isUsefulItem(line, merchantName, couponNumber))
        .where((line) => !_containsMerchantLabel(line))
        .where((line) => !_containsExpiryLabel(line))
        .where((line) => _extractDate(line) == null)
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  DateTime? _parseExpiresAt(String rawText, List<String> lines) {
    for (final line in lines) {
      if (_containsExpiryLabel(line)) {
        final parsed = _extractDate(line);
        if (parsed != null) return parsed;
      }
    }

    return _extractDate(rawText);
  }

  String? _parseCouponNumber(List<String> lines) {
    final candidates = lines
        .map(_clean)
        .where(_looksLikeCouponNumber)
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aDigits = _digitsOnly(a).length;
      final bDigits = _digitsOnly(b).length;
      return bDigits.compareTo(aDigits);
    });

    return _normalizeCouponNumber(candidates.first);
  }

  bool _containsMerchantLabel(String text) {
    final normalized = text.replaceAll(' ', '');
    return normalized.contains('사용처') ||
        normalized.contains('교환처') ||
        normalized.contains('브랜드');
  }

  bool _containsItemLabel(String text) {
    final normalized = text.replaceAll(' ', '');
    return normalized.contains('상품명') ||
        normalized.contains('메뉴명');
  }

  bool _containsExpiryLabel(String text) {
    final normalized = text.replaceAll(' ', '');
    return normalized.contains('유효기간') ||
        normalized.contains('사용기한') ||
        normalized.contains('사용기간') ||
        normalized.contains('만료일') ||
        normalized.contains('까지');
  }

  String? _extractValueAfterLabel(String text) {
    final normalized = text.replaceAll('：', ':');

    if (normalized.contains(':')) {
      final parts = normalized.split(':');
      if (parts.length >= 2) {
        final candidate = _clean(parts.sublist(1).join(':'));
        if (_isUseful(candidate)) return candidate;
      }
    }

    final spaced = normalized.split(RegExp(r'\s{2,}'));
    if (spaced.length >= 2) {
      final candidate = _clean(spaced.last);
      if (_isUseful(candidate)) return candidate;
    }

    return null;
  }

  DateTime? _extractDate(String text) {
    final patterns = [
      RegExp(r'(20\d{2})[./-](\d{1,2})[./-](\d{1,2})'),
      RegExp(r'(20\d{2})년\s*(\d{1,2})월\s*(\d{1,2})일'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      try {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        return DateTime(year, month, day, 23, 59, 59);
      } catch (_) {}
    }

    return null;
  }

  bool _looksLikeCouponNumber(String text) {
    final digits = _digitsOnly(text);
    return digits.length >= 8 && digits.length <= 24;
  }

  String _normalizeCouponNumber(String text) {
    return text
        .replaceAll(RegExp(r'[^0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _digitsOnly(String text) {
    return text.replaceAll(RegExp(r'\D'), '');
  }

  String _clean(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isUseful(String? text) {
    return text != null && text.trim().length >= 2;
  }

  bool _isUsefulItem(
      String? text,
      String? merchantName,
      String? couponNumber,
      ) {
    if (!_isUseful(text)) return false;

    final cleaned = _clean(text!);
    if (merchantName != null && cleaned == merchantName) return false;
    if (couponNumber != null && cleaned == couponNumber) return false;
    if (_looksLikeCouponNumber(cleaned)) return false;
    if (cleaned.length > 50) return false;

    return true;
  }
}