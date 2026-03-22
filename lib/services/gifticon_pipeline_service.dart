import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';

class GifticonPipelineService {
  GifticonPipelineService({
    required this.imagePicker,
    required this.ocrModule,
    required this.detector,
    required this.aiParser,
  });

  final GifticonImagePickerModule imagePicker;
  final GifticonOcrModule ocrModule;
  final GifticonDetectorModule detector;
  final RemoteGifticonAiParser aiParser;

  Future<GifticonPipelineOutput?> run() async {
    final picked = await imagePicker.pickFromGallery();
    if (picked == null) {
      debugPrint('[Gifticon] image pick cancelled');
      return null;
    }

    debugPrint('[Gifticon] picked image: ${picked.path}');

    final ocr = await ocrModule.recognizeText(picked.path);
    debugPrint('[Gifticon][OCR] ${ocr.rawText}');

    final detection = detector.detect(ocr);
    debugPrint('[Gifticon][Matched] ${detection.matchedSignals.join(', ')}');
    debugPrint('[Gifticon][Score] ${detection.score}');
    debugPrint('[Gifticon][IsGifticon] ${detection.isGifticon}');

    if (!detection.isGifticon) {
      debugPrint('[Gifticon] detector rejected image');
      return GifticonPipelineOutput(
        pickedImage: picked,
        detection: detection,
        parsedInfo: null,
      );
    }

    debugPrint('[Gifticon] calling remote parser...');

    final parsedInfo = await aiParser.parse(rawText: ocr.rawText);

    debugPrint('[Gifticon][ParsedInfo] $parsedInfo');

    return GifticonPipelineOutput(
      pickedImage: picked,
      detection: detection,
      parsedInfo: parsedInfo,
    );
  }
}

class GifticonPipelineOutput {
  final PickedImageData pickedImage;
  final GifticonDetectionResult detection;
  final GifticonInfo? parsedInfo;

  const GifticonPipelineOutput({
    required this.pickedImage,
    required this.detection,
    required this.parsedInfo,
  });
}