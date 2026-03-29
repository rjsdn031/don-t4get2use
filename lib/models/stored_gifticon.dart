class StoredGifticon {
  final String id;
  final String imagePath;
  final String? merchantName;
  final String? itemName;
  final DateTime? expiresAt;
  final String? couponNumber;
  final DateTime createdAt;
  final DateTime? usedAt;

  const StoredGifticon({
    required this.id,
    required this.imagePath,
    required this.merchantName,
    required this.itemName,
    required this.expiresAt,
    required this.couponNumber,
    required this.createdAt,
    this.usedAt,
  });

  /// 사용자가 직접 '사용함' 처리한 경우
  bool get isUsed => usedAt != null;

  /// 만료일이 지난 경우 (사용 여부와 무관)
  bool get isExpired {
    if (expiresAt == null) return false;
    final today = DateTime.now();
    final expiry = DateTime(expiresAt!.year, expiresAt!.month, expiresAt!.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    return expiry.isBefore(todayDate);
  }

  /// 리스트에서 비활성 처리할 조건
  bool get isInactive => isUsed || isExpired;

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'merchantName': merchantName,
    'itemName': itemName,
    'expiresAt': expiresAt?.toIso8601String(),
    'couponNumber': couponNumber,
    'createdAt': createdAt.toIso8601String(),
    'usedAt': usedAt?.toIso8601String(),
  };

  factory StoredGifticon.fromJson(Map<dynamic, dynamic> json) {
    return StoredGifticon(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      merchantName: json['merchantName'] as String?,
      itemName: json['itemName'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      couponNumber: json['couponNumber'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      usedAt: json['usedAt'] != null
          ? DateTime.tryParse(json['usedAt'] as String)
          : null,
    );
  }

  StoredGifticon copyWith({
    String? id,
    String? imagePath,
    String? merchantName,
    String? itemName,
    DateTime? expiresAt,
    String? couponNumber,
    DateTime? createdAt,
    DateTime? usedAt,
  }) {
    return StoredGifticon(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      merchantName: merchantName ?? this.merchantName,
      itemName: itemName ?? this.itemName,
      expiresAt: expiresAt ?? this.expiresAt,
      couponNumber: couponNumber ?? this.couponNumber,
      createdAt: createdAt ?? this.createdAt,
      usedAt: usedAt ?? this.usedAt,
    );
  }
}