import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'gifticon_worker_dispatcher.dart';

class GifticonWorkService {
  Future<void> enqueueParseWork({
    required String rawText,
    required String imagePath,
  }) async {
    await Workmanager().registerOneOffTask(
      'gifticon-parse-${DateTime.now().millisecondsSinceEpoch}',
      kGifticonParseTask,
      inputData: {
        kInputRawText: rawText,
        kInputImagePath: imagePath,
      },
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  Future<void> scheduleAutoShareWork({
    required String gifticonId,
    required Duration initialDelay,
  }) async {
    final uniqueName = 'gifticon-auto-share-$gifticonId';

    debugPrint(
      '[Gifticon][Work] scheduleAutoShareWork id=$gifticonId delay=$initialDelay',
    );

    await Workmanager().registerOneOffTask(
      uniqueName,
      kGifticonAutoShareTask,
      inputData: {
        kInputGifticonId: gifticonId,
      },
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  Future<void> cancelAutoShareWork(String gifticonId) async {
    final uniqueName = 'gifticon-auto-share-$gifticonId';

    debugPrint('[Gifticon][Work] cancelAutoShareWork id=$gifticonId');

    await Workmanager().cancelByUniqueName(uniqueName);
  }
}