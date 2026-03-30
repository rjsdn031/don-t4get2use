import 'debug_time_controller.dart';
import 'now_provider.dart';

class DebugNowProvider implements NowProvider {
  DebugNowProvider(this.controller);

  final DebugTimeController controller;

  @override
  DateTime now() => controller.now();
}