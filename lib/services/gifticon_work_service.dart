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
}