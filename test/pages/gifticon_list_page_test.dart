import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dont4get2use2/models/stored_gifticon.dart';
import 'package:dont4get2use2/pages/gifticon_list_page.dart';
import 'package:dont4get2use2/services/device_id_service.dart';
import 'package:dont4get2use2/services/fcm_service.dart';
import 'package:dont4get2use2/services/gifticon_notification_service.dart';
import 'package:dont4get2use2/services/gifticon_pipeline_service.dart';
import 'package:dont4get2use2/services/gifticon_services.dart';
import 'package:dont4get2use2/services/gifticon_sharing_service.dart';
import 'package:dont4get2use2/services/gifticon_storage_service.dart';
import 'package:dont4get2use2/services/gifticon_work_service.dart';
import 'package:dont4get2use2/services/screenshot_automation_service.dart';

class MockGifticonStorageService extends Mock
    implements GifticonStorageService {}

class MockGifticonNotificationService extends Mock
    implements GifticonNotificationService {}

class MockGifticonPipelineService extends Mock
    implements GifticonPipelineService {}

class MockGifticonWorkService extends Mock implements GifticonWorkService {}

class MockScreenshotAutomationService extends Mock
    implements ScreenshotAutomationService {}

class MockDeviceIdService extends Mock implements DeviceIdService {}

class MockGifticonSharingService extends Mock
    implements GifticonSharingService {}

class MockFcmService extends Mock implements FcmService {}

void main() {
  late MockGifticonStorageService storageService;
  late MockGifticonNotificationService notificationService;
  late MockGifticonPipelineService pipelineService;
  late MockGifticonWorkService workService;
  late MockScreenshotAutomationService automationService;
  late MockDeviceIdService deviceIdService;
  late MockGifticonSharingService sharingService;
  late MockFcmService fcmService;
  late GifticonServices services;

  StoredGifticon makeGifticon({
    String id = 'g1',
    String imagePath = '/tmp/g1.jpg',
    String? merchantName = '스타벅스',
    String? itemName = '아메리카노',
    DateTime? expiresAt,
    String? couponNumber = '1234',
    DateTime? createdAt,
    DateTime? usedAt,
    DateTime? sharedAt,
    String? receivedFrom,
    String? ownerNickname,
    String? usedByNickname,
  }) {
    return StoredGifticon(
      id: id,
      imagePath: imagePath,
      merchantName: merchantName,
      itemName: itemName,
      expiresAt: expiresAt ?? DateTime(2026, 4, 10),
      couponNumber: couponNumber,
      createdAt: createdAt ?? DateTime(2026, 3, 30),
      usedAt: usedAt,
      sharedAt: sharedAt,
      receivedFrom: receivedFrom,
      ownerNickname: ownerNickname,
      usedByNickname: usedByNickname,
    );
  }

  setUp(() {
    storageService = MockGifticonStorageService();
    notificationService = MockGifticonNotificationService();
    pipelineService = MockGifticonPipelineService();
    workService = MockGifticonWorkService();
    automationService = MockScreenshotAutomationService();
    deviceIdService = MockDeviceIdService();
    sharingService = MockGifticonSharingService();
    fcmService = MockFcmService();

    services = GifticonServices(
      storageService: storageService,
      notificationService: notificationService,
      pipelineService: pipelineService,
      workService: workService,
      automationService: automationService,
      deviceIdService: deviceIdService,
      sharingService: sharingService,
      fcmService: fcmService,
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GifticonListPage(
          servicesOverride: services,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('저장된 기프티콘이 없으면 안내 문구를 보여준다', (tester) async {
    when(() => storageService.getAllGifticons())
        .thenReturn(<StoredGifticon>[]);
    when(() => deviceIdService.getNickname())
        .thenAnswer((_) async => null);

    await pumpPage(tester);

    expect(find.textContaining('저장된 기프티콘'), findsOneWidget);
  });

  testWidgets('닉네임이 있으면 상단 인사말을 보여준다', (tester) async {
    when(() => storageService.getAllGifticons())
        .thenReturn(<StoredGifticon>[]);
    when(() => deviceIdService.getNickname())
        .thenAnswer((_) async => '반짝이는수달');

    await pumpPage(tester);

    expect(find.textContaining('반짝이는수달'), findsOneWidget);
  });

  testWidgets('sharedAt 이 있으면 공유됨 배지를 보여준다', (tester) async {
    when(() => storageService.getAllGifticons()).thenReturn(
      <StoredGifticon>[
        makeGifticon(
          id: 'g1',
          sharedAt: DateTime(2026, 3, 30, 12),
        ),
      ],
    );
    when(() => deviceIdService.getNickname())
        .thenAnswer((_) async => '반짝이는수달');

    await pumpPage(tester);

    expect(find.textContaining('공유'), findsWidgets);
    expect(find.textContaining('아메리카노'), findsOneWidget);
  });
}