import 'package:flutter/foundation.dart';

import '../models/gifticon_models.dart';
import '../models/local_image_data.dart';
import '../models/stored_gifticon.dart';
import '../modules/gifticon_detector_module.dart';
import '../modules/image_picker_module.dart';
import '../modules/ocr_module.dart';
import '../modules/remote_gifticon_ai_parser.dart';
import 'gifticon_notification_service.dart';
import 'gifticon_storage_service.dart';

class GifticonPipelineService {
  GifticonPipelineService({
    required this.imagePicker,
    required this.ocrModule,
    required this.detector,
    required this.aiParser,
    required this.storageService,
    required this.notificationService,
  });

  final GifticonImagePickerModule imagePicker;
  final GifticonOcrModule ocrModule;
  final GifticonDetectorModule detector;
  final RemoteGifticonAiParser aiParser;
  final GifticonStorageService storageService;
  final GifticonNotificationService notificationService;

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
    debugPrint('[Gifticon][OCR] ${ocr.rawText}');

    final detection = detector.detect(ocr);
    debugPrint('[Gifticon][Matched] ${detection.matchedSignals.join(', ')}');
    debugPrint('[Gifticon][Score] ${detection.score}');
    debugPrint('[Gifticon][IsGifticon] ${detection.isGifticon}');

    if (!detection.isGifticon) {
      debugPrint('[Gifticon][Pipeline] detector rejected image');
      return GifticonPipelineOutput(
        image: image,
        ocr: ocr,
        detection: detection,
        parsedInfo: null,
        storedGifticon: null,
      );
    }

    await notificationService.showProcessingNotification();

    try {
      debugPrint('[Gifticon][Pipeline] calling remote parser...');
      final parsedInfo = await aiParser.parse(rawText: ocr.rawText);
      debugPrint('[Gifticon][ParsedInfo] ${parsedInfo.toJson()}');

      debugPrint('[Gifticon][Pipeline] saving parsed gifticon...');
      final storedGifticon = await storageService.saveGifticon(
        sourceImagePath: image.path,
        info: parsedInfo,
      );

      debugPrint('[Gifticon][Pipeline] saved gifticon id=${storedGifticon.id}');
      await notificationService.showSavedNotificationFromStored(storedGifticon);

      return GifticonPipelineOutput(
        image: image,
        ocr: ocr,
        detection: detection,
        parsedInfo: parsedInfo,
        storedGifticon: storedGifticon,
      );
    } catch (e, st) {
      debugPrint('[Gifticon][Pipeline][Error] $e');
      debugPrint('$st');

      await notificationService.cancelProcessingNotification();

      return GifticonPipelineOutput(
        image: image,
        ocr: ocr,
        detection: detection,
        parsedInfo: null,
        storedGifticon: null,
      );
    }
  }
}

class GifticonPipelineOutput {
  final LocalImageData image;
  final OcrResult ocr;
  final GifticonDetectionResult detection;
  final GifticonInfo? parsedInfo;
  final StoredGifticon? storedGifticon;

  const GifticonPipelineOutput({
    required this.image,
    required this.ocr,
    required this.detection,
    required this.parsedInfo,
    required this.storedGifticon,
  });

  bool get isSaved => storedGifticon != null;
  bool get isGifticon => detection.isGifticon;
}