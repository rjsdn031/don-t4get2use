import 'package:flutter/foundation.dart';

class DebugTimeController extends ChangeNotifier {
  DateTime? _fixedNow;

  DateTime? get fixedNow => _fixedNow;
  bool get isEnabled => _fixedNow != null;

  DateTime now() => _fixedNow ?? DateTime.now();

  void setFixedNow(DateTime value) {
    _fixedNow = value;
    notifyListeners();
  }

  void clear() {
    _fixedNow = null;
    notifyListeners();
  }

  String get label {
    final value = fixedNow;
    if (value == null) return 'system';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}