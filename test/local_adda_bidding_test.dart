import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezmoov_partner_app/models/bid_model.dart';
import 'package:ezmoov_partner_app/models/booking_model.dart';
import 'package:ezmoov_partner_app/viewmodels/ride_request_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
  });
  group('BidModel Unit Tests', () {
    test('Parses BidModel from JSON correctly', () {
      final json = {
        'id': 'bid-123',
        'booking_id': 'booking-456',
        'driver_id': 'driver-789',
        'current_booking_rate': 250.0,
        'driver_bid': 280.0,
        'status': 'pending',
        'created_at': '2026-09-23T20:00:00.000Z',
      };

      final bid = BidModel.fromJson(json);
      expect(bid.id, equals('bid-123'));
      expect(bid.bookingId, equals('booking-456'));
      expect(bid.driverId, equals('driver-789'));
      expect(bid.currentBookingRate, equals(250.0));
      expect(bid.driverBid, equals(280.0));
      expect(bid.status, equals('pending'));
      expect(bid.createdAt, isNotNull);
    });

    test('Serializes BidModel to JSON correctly', () {
      final bid = BidModel(
        id: 'bid-999',
        bookingId: 'booking-888',
        driverId: 'driver-777',
        currentBookingRate: 300.0,
        driverBid: 350.0,
        status: 'accepted',
      );

      final json = bid.toJson();
      expect(json['id'], equals('bid-999'));
      expect(json['booking_id'], equals('booking-888'));
      expect(json['driver_id'], equals('driver-777'));
      expect(json['current_booking_rate'], equals(300.0));
      expect(json['driver_bid'], equals(350.0));
      expect(json['status'], equals('accepted'));
    });

    test('copyWith updates specified fields correctly', () {
      final bid = BidModel(
        id: 'bid-1',
        bookingId: 'b-1',
        driverId: 'd-1',
        currentBookingRate: 100.0,
        driverBid: 120.0,
        status: 'pending',
      );

      final updated = bid.copyWith(status: 'accepted', driverBid: 150.0);
      expect(updated.status, equals('accepted'));
      expect(updated.driverBid, equals(150.0));
      expect(updated.bookingId, equals('b-1'));
    });
  });

  group('Local Adda 20 km Discovery & Bidding Eligibility Tests', () {
    late RideRequestViewModel vm;

    setUp(() {
      vm = RideRequestViewModel();
    });

    test('Local Adda booking WITHIN 20 km is ELIGIBLE', () {
      // Driver at (12.9716, 77.5946)
      // Pickup ~15 km away at (13.1000, 77.5946)
      final booking = BookingModel(
        id: 'booking-local-adda-1',
        customerId: 'cust-1',
        pickupAddress: 'Yelahanka, Bengaluru',
        dropAddress: 'Majestic, Bengaluru',
        pickupLat: 13.1000,
        pickupLng: 77.5946,
        dropLat: 12.9716,
        dropLng: 77.5946,
        amount: {'base_fare': 450.0},
        service: 'local_adda',
        status: 'searching',
      );

      final isEligible = vm.isBookingEligibleForDriver(
        booking: booking,
        driverLat: 12.9716,
        driverLng: 77.5946,
      );

      expect(isEligible, isTrue);
    });

    test('Local Adda booking EXCEEDING 20 km (e.g. 25 km) is INELIGIBLE', () {
      // Driver at (12.9716, 77.5946)
      // Pickup ~25 km away at (13.2000, 77.5946)
      final booking = BookingModel(
        id: 'booking-local-adda-2',
        customerId: 'cust-2',
        pickupAddress: 'Doddaballapur, Bengaluru',
        dropAddress: 'Majestic, Bengaluru',
        pickupLat: 13.2000,
        pickupLng: 77.5946,
        dropLat: 12.9716,
        dropLng: 77.5946,
        amount: {'base_fare': 750.0},
        service: 'local_adda',
        status: 'searching',
      );

      final isEligible = vm.isBookingEligibleForDriver(
        booking: booking,
        driverLat: 12.9716,
        driverLng: 77.5946,
      );

      expect(isEligible, isFalse);
    });

    test('Supports bidding_local_adda and localadda service aliases', () {
      final booking1 = BookingModel(
        id: 'booking-alias-1',
        customerId: 'cust-3',
        pickupAddress: 'Indiranagar',
        dropAddress: 'Koramangala',
        pickupLat: 12.9784,
        pickupLng: 77.6408,
        dropLat: 12.9352,
        dropLng: 77.6245,
        amount: {'base_fare': 200.0},
        service: 'bidding_local_adda',
        status: 'searching',
      );

      final booking2 = BookingModel(
        id: 'booking-alias-2',
        customerId: 'cust-4',
        pickupAddress: 'Indiranagar',
        dropAddress: 'Koramangala',
        pickupLat: 12.9784,
        pickupLng: 77.6408,
        dropLat: 12.9352,
        dropLng: 77.6245,
        amount: {'base_fare': 200.0},
        service: 'localadda',
        status: 'searching',
      );

      expect(
        vm.isBookingEligibleForDriver(
          booking: booking1,
          driverLat: 12.9716,
          driverLng: 77.5946,
        ),
        isTrue,
      );

      expect(
        vm.isBookingEligibleForDriver(
          booking: booking2,
          driverLat: 12.9716,
          driverLng: 77.5946,
        ),
        isTrue,
      );
    });
  });
}
