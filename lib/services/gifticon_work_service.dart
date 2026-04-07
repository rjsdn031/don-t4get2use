import 'package:workmanager/workmanager.dart';

import 'app_logger.dart';
import 'gifticon_worker_dispatcher.dart';

class GifticonWorkService {
  Future<void> enqueueParseWork({
    required String rawText,
    required String imagePath,
  }) async {
    final taskName = 'gifticon-parse-${DateTime.now().millisecondsSinceEpoch}';

    await AppLogger.log(
      tag: 'Work',
      event: 'enqueue_parse_work',
      data: {
        'taskName': taskName,
        'rawTextLength': rawText.length,
        'imagePath': imagePath,
      },
    );

    await Workmanager().registerOneOffTask(
      taskName,
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

    await AppLogger.log(
      tag: 'Work',
      event: 'schedule_auto_share_work',
      data: {
        'id': gifticonId,
        'delay': initialDelay.toString(),
        'uniqueName': uniqueName,
      },
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

    await AppLogger.log(
      tag: 'Work',
      event: 'cancel_auto_share_work',
      data: {
        'id': gifticonId,
        'uniqueName': uniqueName,
      },
    );

    await Workmanager().cancelByUniqueName(uniqueName);
  }
}