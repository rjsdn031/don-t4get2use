import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../models/gifticon_models.dart';

class GifticonBarcodeModule {
  GifticonBarcodeModule()
      : _scanner = BarcodeScanner(
    formats: [
      BarcodeFormat.all,
    ],
  );

  final BarcodeScanner _scanner;

  Future<BarcodeDetectionResult> scan(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final barcodes = await _scanner.processImage(inputImage);

    bool hasBarcodeLike = false;
    bool hasQrLike = false;
    final rawValues = <String>[];

    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        rawValues.add(rawValue);
      }

      if (barcode.format == BarcodeFormat.qrCode) {
        hasQrLike = true;
      } else {
        hasBarcodeLike = true;
      }
    }

    return BarcodeDetectionResult(
      hasBarcodeLike: hasBarcodeLike,
      hasQrLike: hasQrLike,
      rawValues: rawValues,
    );
  }

  void dispose() {
    _scanner.close();
  }
}