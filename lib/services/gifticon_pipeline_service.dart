import '../models/gifticon_models.dart';
import '../models/local_image_data.dart';
import '../modules/barcode_module.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../services/app_logger.dart';

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
      await AppLogger.log(
        tag: 'Pipeline',
        event: 'image_pick_cancelled',
      );
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
    await AppLogger.log(
      tag: 'Pipeline',
      event: 'analyze_start',
      data: {
        'path': image.path,
        'fileName': image.fileName,
        'sizeBytes': image.sizeBytes,
      },
    );

    final ocr = await ocrModule.recognizeText(image.path);

    await AppLogger.log(
      tag: 'Pipeline',
      event: 'ocr_finished',
      data: {
        'rawTextLength': ocr.rawText.length,
        'rawText': ocr.rawText,
      },
    );

    final barcode = await barcodeModule.scan(image.path);

    await AppLogger.log(
      tag: 'Pipeline',
      event: 'barcode_finished',
      data: {
        'hasBarcodeLike': barcode.hasBarcodeLike,
        'hasQrLike': barcode.hasQrLike,
        'rawValues': barcode.rawValues,
      },
    );

    final detection = detector.detect(ocr, barcode);

    await AppLogger.log(
      tag: 'Pipeline',
      event: 'detection_finished',
      data: {
        'matchedSignals': detection.matchedSignals,
        'score': detection.score,
        'isGifticon': detection.isGifticon,
      },
    );

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