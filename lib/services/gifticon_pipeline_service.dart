import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/gifticon_parser_module.dart';
import '../modules/gifticon_upload_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';

class GifticonPipelineService {
  GifticonPipelineService({
    required this.imagePicker,
    required this.ocrModule,
    required this.detector,
    required this.parser,
    required this.uploadModule,
  });

  final GifticonImagePickerModule imagePicker;
  final GifticonOcrModule ocrModule;
  final GifticonDetectorModule detector;
  final GifticonParserModule parser;
  final GifticonUploadModule uploadModule;

  Future<GifticonPipelineOutput?> run({
    required String ownerUserId,
  }) async {
    final picked = await imagePicker.pickFromGallery();
    if (picked == null) return null;

    final ocr = await ocrModule.recognizeText(picked.path);
    final detection = detector.detect(ocr);

    debugPrint('[Gifticon][OCR] ${detection.ocr.rawText}');
    debugPrint('[Gifticon][Matched] ${detection.matchedSignals.join(', ')}');
    debugPrint('[Gifticon][Score] ${detection.score}');

    if (!detection.isGifticon) {
      return GifticonPipelineOutput(
        pickedImage: picked,
        detection: detection,
        parsedInfo: null,
        uploaded: null,
      );
    }

    final parsed = parser.parse(ocr);

    GifticonSaveResponse? uploaded;
    try {
      uploaded = await uploadModule.uploadGifticon(
        GifticonSavePayload(
          ownerUserId: ownerUserId,
          imagePath: picked.path,
          info: parsed,
        ),
      );
    } catch (e) {
      debugPrint('[Gifticon][UploadError] $e');
      uploaded = null;
    }

    return GifticonPipelineOutput(
      pickedImage: picked,
      detection: detection,
      parsedInfo: parsed,
      // uploaded: uploaded,
      uploaded: null,
    );
  }
}

class GifticonPipelineOutput {
  final PickedImageData pickedImage;
  final GifticonDetectionResult detection;
  final GifticonInfo? parsedInfo;
  final GifticonSaveResponse? uploaded;

  const GifticonPipelineOutput({
    required this.pickedImage,
    required this.detection,
    required this.parsedInfo,
    required this.uploaded,
  });
}