import 'package:flutter_test/flutter_test.dart';
import 'package:dont4get2use2/models/stored_gifticon.dart';

void main() {
  StoredGifticon makeGifticon({
    DateTime? expiresAt,
    DateTime? usedAt,
  }) {
    return StoredGifticon(
      id: 'g1',
      imagePath: '/tmp/g1.jpg',
      merchantName: '스타벅스',
      itemName: '아메리카노',
      expiresAt: expiresAt,
      couponNumber: '1234',
      createdAt: DateTime(2026, 3, 30),
      usedAt: usedAt,
    );
  }

  group('StoredGifticon time logic', () {
    test('유효기간 당일은 만료가 아니다', () {
      final gifticon = makeGifticon(
        expiresAt: DateTime(2026, 3, 30, 23, 59),
      );

      final now = DateTime(2026, 3, 30, 9, 0);

      expect(gifticon.isExpiredAt(now), false);
      expect(gifticon.isInactiveAt(now), false);
    });

    test('유효기간 다음 날은 만료다', () {
      final gifticon = makeGifticon(
        expiresAt: DateTime(2026, 3, 30, 23, 59),
      );

      final now = DateTime(2026, 3, 31, 9, 0);

      expect(gifticon.isExpiredAt(now), true);
      expect(gifticon.isInactiveAt(now), true);
    });

    test('사용된 기프티콘은 날짜와 무관하게 inactive다', () {
      final gifticon = makeGifticon(
        expiresAt: DateTime(2026, 4, 10),
        usedAt: DateTime(2026, 3, 30, 10, 0),
      );

      final now = DateTime(2026, 3, 30, 12, 0);

      expect(gifticon.isInactiveAt(now), true);
    });

    test('expiresAt 이 없으면 만료가 아니다', () {
      final gifticon = makeGifticon();
      final now = DateTime(2026, 3, 31, 9, 0);

      expect(gifticon.isExpiredAt(now), false);
      expect(gifticon.isInactiveAt(now), false);
    });
  });
}