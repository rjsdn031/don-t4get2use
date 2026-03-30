class StoredGifticon {
  final String id;
  final String imagePath;
  final String? merchantName;
  final String? itemName;
  final DateTime? expiresAt;
  final String? couponNumber;
  final DateTime createdAt;
  final DateTime? usedAt;
  final DateTime? sharedAt;
  final String? receivedFrom;
  final String? ownerNickname;
  final String? usedByNickname;

  const StoredGifticon({
    required this.id,
    required this.imagePath,
    required this.merchantName,
    required this.itemName,
    required this.expiresAt,
    required this.couponNumber,
    required this.createdAt,
    this.usedAt,
    this.sharedAt,
    this.receivedFrom,
    this.ownerNickname,
    this.usedByNickname,
  });

  bool get isUsed => usedAt != null;
  bool get isShared => sharedAt != null;
  bool get isReceived => receivedFrom != null;

  bool isExpiredAt(DateTime now) {
    if (expiresAt == null) return false;
    final expiry = DateTime(expiresAt!.year, expiresAt!.month, expiresAt!.day);
    final today = DateTime(now.year, now.month, now.day);
    return expiry.isBefore(today);
  }

  bool isInactiveAt(DateTime now) => isUsed || isExpiredAt(now);

  bool get isExpired => isExpiredAt(DateTime.now());
  bool get isInactive => isInactiveAt(DateTime.now());

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'merchantName': merchantName,
    'itemName': itemName,
    'expiresAt': expiresAt?.toIso8601String(),
    'couponNumber': couponNumber,
    'createdAt': createdAt.toIso8601String(),
    'usedAt': usedAt?.toIso8601String(),
    'sharedAt': sharedAt?.toIso8601String(),
    'receivedFrom': receivedFrom,
    'ownerNickname': ownerNickname,
    'usedByNickname': usedByNickname,
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
      sharedAt: json['sharedAt'] != null
          ? DateTime.tryParse(json['sharedAt'] as String)
          : null,
      receivedFrom: json['receivedFrom'] as String?,
      ownerNickname: json['ownerNickname'] as String?,
      usedByNickname: json['usedByNickname'] as String?,
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
    DateTime? sharedAt,
    String? receivedFrom,
    String? ownerNickname,
    String? usedByNickname,
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
      sharedAt: sharedAt ?? this.sharedAt,
      receivedFrom: receivedFrom ?? this.receivedFrom,
      ownerNickname: ownerNickname ?? this.ownerNickname,
      usedByNickname: usedByNickname ?? this.usedByNickname,
    );
  }
}