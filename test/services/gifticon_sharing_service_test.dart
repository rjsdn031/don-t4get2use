import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dont4get2use2/models/stored_gifticon.dart';
import 'package:dont4get2use2/services/device_id_service.dart';
import 'package:dont4get2use2/services/gifticon_sharing_service.dart';
import 'package:dont4get2use2/services/gifticon_storage_service.dart';

class MockDio extends Mock implements Dio {}

class MockGifticonStorageService extends Mock
    implements GifticonStorageService {}

class MockDeviceIdService extends Mock implements DeviceIdService {}

class FakeOptions extends Fake implements Options {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeOptions());
    registerFallbackValue(FakeRequestOptions());
  });

  late MockDio dio;
  late MockGifticonStorageService storageService;
  late MockDeviceIdService deviceIdService;
  late GifticonSharingService service;

  StoredGifticon makeStored({
    String id = 'g1',
    String imagePath = '/tmp/g1.jpg',
    DateTime? sharedAt,
  }) {
    return StoredGifticon(
      id: id,
      imagePath: imagePath,
      merchantName: '스타벅스',
      itemName: '아메리카노',
      expiresAt: DateTime(2026, 4, 10),
      couponNumber: '1234',
      createdAt: DateTime(2026, 3, 30),
      sharedAt: sharedAt,
    );
  }

  setUp(() {
    dio = MockDio();
    storageService = MockGifticonStorageService();
    deviceIdService = MockDeviceIdService();

    service = GifticonSharingService(
      baseUrl: 'https://example.com',
      storageService: storageService,
      deviceIdService: deviceIdService,
      dio: dio,
    );
  });

  group('uploadForSharing', () {
    test('이미 sharedAt 이 있으면 아무 것도 하지 않는다', () async {
      final stored = makeStored(sharedAt: DateTime(2026, 3, 30));

      await service.uploadForSharing(stored);

      verifyNever(() => deviceIdService.getDeviceId());
      verifyNever(
            () => dio.post<void>(
          any(),
          data: any(named: 'data'),
        ),
      );
      verifyNever(() => storageService.markAsShared(any()));
    });

    test('이미지 파일이 없으면 업로드하지 않는다', () async {
      final stored = makeStored(imagePath: '/tmp/not_found.jpg');

      when(() => deviceIdService.getDeviceId())
          .thenAnswer((_) async => 'device-1');

      await service.uploadForSharing(stored);

      verify(() => deviceIdService.getDeviceId()).called(1);
      verifyNever(
            () => dio.post<void>(
          any(),
          data: any(named: 'data'),
        ),
      );
      verifyNever(() => storageService.markAsShared(any()));
    });

    test('정상 업로드 시 share API 호출 후 markAsShared 를 호출한다', () async {
      final tempDir = await Directory.systemTemp.createTemp('gifticon_test');
      final imageFile = File('${tempDir.path}/g1.jpg');
      await imageFile.writeAsBytes([1, 2, 3, 4]);

      final stored = makeStored(imagePath: imageFile.path);

      when(() => deviceIdService.getDeviceId())
          .thenAnswer((_) async => 'device-1');

      when(
            () => dio.post<void>(
          '/api/gifticons/share',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
            (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/api/gifticons/share'),
          statusCode: 201,
        ),
      );

      when(() => storageService.markAsShared('g1'))
          .thenAnswer((_) async {});

      await service.uploadForSharing(stored);

      verify(() => deviceIdService.getDeviceId()).called(1);

      verify(
            () => dio.post<void>(
          '/api/gifticons/share',
          data: any(
            named: 'data',
            that: allOf([
              containsPair('gifticonId', 'g1'),
              containsPair('ownerId', 'device-1'),
              containsPair('merchantName', '스타벅스'),
              containsPair('itemName', '아메리카노'),
              containsPair('couponNumber', '1234'),
            ]),
          ),
        ),
      ).called(1);

      verify(() => storageService.markAsShared('g1')).called(1);
    });

    test('업로드 실패 시 markAsShared 를 호출하지 않는다', () async {
      final tempDir = await Directory.systemTemp.createTemp('gifticon_test');
      final imageFile = File('${tempDir.path}/g1.jpg');
      await imageFile.writeAsBytes([1, 2, 3, 4]);

      final stored = makeStored(imagePath: imageFile.path);

      when(() => deviceIdService.getDeviceId())
          .thenAnswer((_) async => 'device-1');

      when(
            () => dio.post<void>(
          '/api/gifticons/share',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/gifticons/share'),
          type: DioExceptionType.badResponse,
        ),
      );

      await service.uploadForSharing(stored);

      verify(
            () => dio.post<void>(
          '/api/gifticons/share',
          data: any(named: 'data'),
        ),
      ).called(1);

      verifyNever(() => storageService.markAsShared(any()));
    });
  });

  group('markAsUsedRemote', () {
    test('정상 호출 시 used API 를 호출한다', () async {
      when(() => deviceIdService.getDeviceId())
          .thenAnswer((_) async => 'device-1');

      when(
            () => dio.post<void>(
          '/api/gifticons/used',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
            (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/api/gifticons/used'),
          statusCode: 200,
        ),
      );

      await service.markAsUsedRemote(gifticonId: 'g1');

      verify(() => deviceIdService.getDeviceId()).called(1);
      verify(
            () => dio.post<void>(
          '/api/gifticons/used',
          data: {
            'gifticonId': 'g1',
            'usedBy': 'device-1',
          },
        ),
      ).called(1);
    });

    test('API 실패가 나도 예외를 밖으로 던지지 않는다', () async {
      when(() => deviceIdService.getDeviceId())
          .thenAnswer((_) async => 'device-1');

      when(
            () => dio.post<void>(
          '/api/gifticons/used',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/gifticons/used'),
          type: DioExceptionType.connectionError,
        ),
      );

      await service.markAsUsedRemote(gifticonId: 'g1');

      verify(
            () => dio.post<void>(
          '/api/gifticons/used',
          data: {
            'gifticonId': 'g1',
            'usedBy': 'device-1',
          },
        ),
      ).called(1);
    });
  });

  group('receiveSharedGifticon', () {
    test('다운로드 성공 시 saveReceivedGifticon 을 호출하고 StoredGifticon 을 반환한다',
            () async {
          final saved = StoredGifticon(
            id: 'g1',
            imagePath: '/tmp/saved_g1.jpg',
            merchantName: '스타벅스',
            itemName: '아메리카노',
            expiresAt: DateTime(2026, 4, 10),
            couponNumber: '1234',
            createdAt: DateTime(2026, 3, 30),
            receivedFrom: 'owner-1',
            ownerNickname: '반짝이는수달',
          );

          when(
                () => dio.get<List<int>>(
              'https://example.com/g1.jpg',
              options: any(named: 'options'),
            ),
          ).thenAnswer(
                (_) async => Response<List<int>>(
              requestOptions: RequestOptions(path: 'https://example.com/g1.jpg'),
              data: [1, 2, 3, 4],
              statusCode: 200,
            ),
          );

          when(
                () => storageService.saveReceivedGifticon(
              gifticonId: 'g1',
              localImagePath: any(named: 'localImagePath'),
              merchantName: '스타벅스',
              itemName: '아메리카노',
              couponNumber: '1234',
              expiresAt: DateTime(2026, 4, 10),
              receivedFrom: 'owner-1',
              ownerNickname: '반짝이는수달',
            ),
          ).thenAnswer((_) async => saved);

          final result = await service.receiveSharedGifticon(
            gifticonId: 'g1',
            imageUrl: 'https://example.com/g1.jpg',
            ownerId: 'owner-1',
            ownerNickname: '반짝이는수달',
            merchantName: '스타벅스',
            itemName: '아메리카노',
            couponNumber: '1234',
            expiresAt: DateTime(2026, 4, 10),
          );

          expect(result, isNotNull);
          expect(result!.id, 'g1');
          expect(result.ownerNickname, '반짝이는수달');

          verify(
                () => dio.get<List<int>>(
              'https://example.com/g1.jpg',
              options: any(named: 'options'),
            ),
          ).called(1);

          verify(
                () => storageService.saveReceivedGifticon(
              gifticonId: 'g1',
              localImagePath: any(named: 'localImagePath'),
              merchantName: '스타벅스',
              itemName: '아메리카노',
              couponNumber: '1234',
              expiresAt: DateTime(2026, 4, 10),
              receivedFrom: 'owner-1',
              ownerNickname: '반짝이는수달',
            ),
          ).called(1);
        });

    test('다운로드 실패 시 null 을 반환한다', () async {
      when(
            () => dio.get<List<int>>(
          'https://example.com/g1.jpg',
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'https://example.com/g1.jpg'),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await service.receiveSharedGifticon(
        gifticonId: 'g1',
        imageUrl: 'https://example.com/g1.jpg',
        ownerId: 'owner-1',
        ownerNickname: '반짝이는수달',
        merchantName: '스타벅스',
        itemName: '아메리카노',
        couponNumber: '1234',
        expiresAt: DateTime(2026, 4, 10),
      );

      expect(result, isNull);
      verifyNever(
            () => storageService.saveReceivedGifticon(
          gifticonId: any(named: 'gifticonId'),
          localImagePath: any(named: 'localImagePath'),
          merchantName: any(named: 'merchantName'),
          itemName: any(named: 'itemName'),
          couponNumber: any(named: 'couponNumber'),
          expiresAt: any(named: 'expiresAt'),
          receivedFrom: any(named: 'receivedFrom'),
          ownerNickname: any(named: 'ownerNickname'),
        ),
      );
    });
  });
}