import 'dart:async';
import 'package:flutter/services.dart';

class ScreenshotEventListenerModule {
  static const EventChannel _channel =
  EventChannel('gifticon/screenshot_events');

  Stream<dynamic> get events => _channel.receiveBroadcastStream();
}