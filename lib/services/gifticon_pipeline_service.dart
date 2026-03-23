import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';
import '../models/local_image_data.dart';
import '../modules/barcode_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';

class GifticonPipelineService {
  GifticonPipelineService({
    required this.imagePicker,
    required this.ocrModule,
    required this.barcodeModule,
    required this.detector,
  });

  final GifticonImagePickerModule imagePicker;
  final GifticonOcrModule ocrModule;
  final GifticonBarcodeModule barcodeModule;
  final GifticonDetectorModule detector;

  Future<GifticonPipelineOutput?> runFromGallery() async {
    final picked = await imagePicker.pickFromGallery();
    if (picked == null) {
      debugPrint('[Gifticon][Pipeline] image pick cancelled');
      return null;
    }

    return _analyzeImage(picked);
  }

  Future<GifticonPipelineOutput> runFromImagePath(String imagePath) async {
    return _analyzeImage(LocalImageData(path: imagePath));
  }

  Future<GifticonPipelineOutput> runFromImage(LocalImageData image) async {
    return _analyzeImage(image);
  }

  Future<GifticonPipelineOutput> _analyzeImage(LocalImageData image) async {
    debugPrint('[Gifticon][Pipeline] picked image: ${image.path}');

    final ocr = await ocrModule.recognizeText(image.path);
    debugPrint('[Gifticon][Pipeline] OCR finished');
    debugPrint('[Gifticon][OCR] ${ocr.rawText}');

    final barcode = await barcodeModule.scan(image.path);
    debugPrint('[Gifticon][Barcode] hasBarcodeLike=${barcode.hasBarcodeLike}');
    debugPrint('[Gifticon][Barcode] hasQrLike=${barcode.hasQrLike}');
    debugPrint('[Gifticon][Barcode] rawValues=${barcode.rawValues}');

    final detection = detector.detect(ocr, barcode);
    debugPrint('[Gifticon][Matched] ${detection.matchedSignals.join(', ')}');
    debugPrint('[Gifticon][Score] ${detection.score}');
    debugPrint('[Gifticon][IsGifticon] ${detection.isGifticon}');

    return GifticonPipelineOutput(
      image: image,
      ocr: ocr,
      detection: detection,
    );
  }

  void dispose() {
    ocrModule.dispose();
    barcodeModule.dispose();
  }
}

class GifticonPipelineOutput {
  final LocalImageData image;
  final OcrResult ocr;
  final GifticonDetectionResult detection;

  const GifticonPipelineOutput({
    required this.image,
    required this.ocr,
    required this.detection,
  });

  bool get isGifticon => detection.isGifticon;
}