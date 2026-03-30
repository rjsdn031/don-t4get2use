abstract class NowProvider {
  DateTime now();
}

class SystemNowProvider implements NowProvider {
  @override
  DateTime now() => DateTime.now();
}

class FixedNowProvider implements NowProvider {
  FixedNowProvider(this.fixedNow);

  final DateTime fixedNow;

  @override
  DateTime now() => fixedNow;
}