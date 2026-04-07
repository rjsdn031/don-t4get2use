import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AppLogger {
  AppLogger._();

  static const String _fileName = 'app_logs.jsonl';

  static File? _cachedFile;

  static Future<File> _getLogFile() async {
    if (_cachedFile != null) return _cachedFile!;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');

    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    _cachedFile = file;
    return file;
  }

  static String _nowIso() => DateTime.now().toIso8601String();

  static Object? _sanitizeValue(Object? value, {String? key}) {
    if (value == null) return null;

    if (value is Map<String, dynamic>) {
      return _sanitizeMap(value);
    }

    if (value is Iterable) {
      return value.map((e) => _sanitizeValue(e)).toList();
    }

    if (value is String) {
      final lowerKey = key?.toLowerCase() ?? '';

      final looksLikeCouponField =
          lowerKey.contains('coupon') ||
              lowerKey.contains('barcode') ||
              lowerKey.contains('serial');

      if (looksLikeCouponField) {
        return _maskCouponNumber(value);
      }
    }

    return value;
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    final result = <String, dynamic>{};

    input.forEach((key, value) {
      result[key] = _sanitizeValue(value, key: key);
    });

    return result;
  }

  static String _maskCouponNumber(String value) {
    final compact = value.trim();
    if (compact.isEmpty) return compact;

    // 숫자/문자 혼합이어도 그냥 길이 기준으로 처리
    if (compact.length <= 8) {
      return compact;
    }

    final start = compact.substring(0, 4);
    final end = compact.substring(compact.length - 4);
    final masked = '*' * (compact.length - 8);
    return '$start$masked$end';
  }

  static Future<void> log({
    required String tag,
    required String event,
    Map<String, dynamic>? data,
  }) async {
    final file = await _getLogFile();

    final entry = <String, dynamic>{
      'ts': _nowIso(),
      'tag': tag,
      'event': event,
      if (data != null) 'data': _sanitizeMap(data),
    };

    final line = jsonEncode(entry);

    // 콘솔에도 같이 찍기
    // ignore: avoid_print
    print('[AppLog][$tag][$event] ${entry['data'] ?? {}}');

    await file.writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<String> getLogFilePath() async {
    final file = await _getLogFile();
    return file.path;
  }

  static Future<bool> hasLogs() async {
    final file = await _getLogFile();
    if (!await file.exists()) return false;
    return await file.length() > 0;
  }

  static Future<void> exportLogs() async {
    final file = await _getLogFile();

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('내보낼 로그가 없어요.');
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '앱 로그 파일입니다.',
        subject: 'app_logs.jsonl',
      ),
    );
  }
}