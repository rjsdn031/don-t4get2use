import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';
import '../models/local_image_data.dart';
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

  Future<GifticonPipelineOutput?> runFromGallery() async {
    final picked = await imagePicker.pickFromGallery();
    if (picked == null) {
      debugPrint('[Gifticon] image pick cancelled');
      return null;
    }

    return _analyzeImage(picked);
  }

  Future<GifticonPipelineOutput> runFromImagePath(String imagePath) async {
    final image = LocalImageData(path: imagePath);
    return _analyzeImage(image);
  }

  Future<GifticonPipelineOutput> runFromImage(LocalImageData image) async {
    return _analyzeImage(image);
  }

  Future<GifticonPipelineOutput> _analyzeImage(LocalImageData image) async {
    debugPrint('[Gifticon] picked image: ${image.path}');

    final ocr = await ocrModule.recognizeText(image.path);
    debugPrint('[Gifticon][OCR] ${ocr.rawText}');

    final detection = detector.detect(ocr);
    debugPrint('[Gifticon][Matched] ${detection.matchedSignals.join(', ')}');
    debugPrint('[Gifticon][Score] ${detection.score}');
    debugPrint('[Gifticon][IsGifticon] ${detection.isGifticon}');

    if (!detection.isGifticon) {
      debugPrint('[Gifticon] detector rejected image');
      return GifticonPipelineOutput(
        image: image,
        detection: detection,
        parsedInfo: null,
      );
    }

    debugPrint('[Gifticon] calling remote parser...');

    GifticonInfo? parsedInfo;
    try {
      parsedInfo = await aiParser.parse(rawText: ocr.rawText);
      debugPrint('[Gifticon][ParsedInfo] $parsedInfo');
    } catch (e) {
      debugPrint('[Gifticon][RemoteParser][Error] $e');
      parsedInfo = null;
    }

    return GifticonPipelineOutput(
      image: image,
      detection: detection,
      parsedInfo: parsedInfo,
    );
  }
}

class GifticonPipelineOutput {
  final LocalImageData image;
  final GifticonDetectionResult detection;
  final GifticonInfo? parsedInfo;

  const GifticonPipelineOutput({
    required this.image,
    required this.detection,
    required this.parsedInfo,
  });
}