import '../models/local_image_data.dart';

abstract class LatestImageFinderModule {
  Future<LocalImageData?> findLatestImage();
}