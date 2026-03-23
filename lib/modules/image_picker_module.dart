import 'dart:io';
import 'package:image_picker/image_picker.dart';

import '../models/local_image_data.dart';

class GifticonImagePickerModule {
  GifticonImagePickerModule({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<LocalImageData?> pickFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );

    if (file == null) return null;

    final ioFile = File(file.path);
    final size = await ioFile.length();

    return LocalImageData(
      path: file.path,
      fileName: file.name,
      sizeBytes: size,
    );
  }
}