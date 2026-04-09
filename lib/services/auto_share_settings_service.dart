import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

class AutoShareSettingsService {
  static const String _autoShareEnabledKey = 'auto_share_enabled';

  /// 자동 공유 활성화 여부 조회
  /// 기본값: true (B군 - 공유함)
  Future<bool> isAutoShareEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_autoShareEnabledKey) ?? true;

    await AppLogger.log(
      tag: 'AutoShareSettings',
      event: 'get_auto_share_enabled',
      data: {
        'enabled': enabled,
      },
    );

    return enabled;
  }

  /// 자동 공유 활성화/비활성화 설정
  Future<void> setAutoShareEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoShareEnabledKey, enabled);

    await AppLogger.log(
      tag: 'AutoShareSettings',
      event: 'set_auto_share_enabled',
      data: {
        'enabled': enabled,
      },
    );
  }

  /// 실험군 확인 (A군: false, B군: true)
  Future<String> getExperimentGroup() async {
    final enabled = await isAutoShareEnabled();
    return enabled ? 'B' : 'A';
  }
}