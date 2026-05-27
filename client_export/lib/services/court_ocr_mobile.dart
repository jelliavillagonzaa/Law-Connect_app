import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> extractTextFromImagePath(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final input = InputImage.fromFilePath(path);
    final recognized = await recognizer.processImage(input);
    return recognized.text;
  } catch (_) {
    return '';
  } finally {
    await recognizer.close();
  }
}
