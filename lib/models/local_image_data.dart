class LocalImageData {
  final String path;
  final String? fileName;
  final int? sizeBytes;

  const LocalImageData({
    required this.path,
    this.fileName,
    this.sizeBytes,
  });

  LocalImageData copyWith({
    String? path,
    String? fileName,
    int? sizeBytes,
  }) {
    return LocalImageData(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  @override
  String toString() {
    return 'LocalImageData(path: $path, fileName: $fileName, sizeBytes: $sizeBytes)';
  }
}