class StoredGifticon {
  final String id;
  final String imagePath;
  final String? merchantName;
  final String? itemName;
  final DateTime? expiresAt;
  final String? couponNumber;
  final DateTime createdAt;

  const StoredGifticon({
    required this.id,
    required this.imagePath,
    required this.merchantName,
    required this.itemName,
    required this.expiresAt,
    required this.couponNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'merchantName': merchantName,
    'itemName': itemName,
    'expiresAt': expiresAt?.toIso8601String(),
    'couponNumber': couponNumber,
    'createdAt': createdAt.toIso8601String(),
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
    );
  }
}