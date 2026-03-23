import '../models/local_image_data.dart';
import 'latest_image_finder_module.dart';

class StubLatestImageFinderModule implements LatestImageFinderModule {
  @override
  Future<LocalImageData?> findLatestImage() async {
    return null;
  }
}