import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/gifticon_models.dart';

class GifticonOcrModule {
  GifticonOcrModule()
      : _recognizer = TextRecognizer(script: TextRecognitionScript.korean);

  final TextRecognizer _recognizer;

  Future<OcrResult> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _recognizer.processImage(inputImage);

    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty) {
          lines.add(text);
        }
      }
    }

    return OcrResult(
      rawText: recognizedText.text,
      lines: lines,
    );
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}