import 'package:flutter_test/flutter_test.dart';
import 'package:ezmoov_partner_app/viewmodels/ride_request_viewmodel.dart';

import 'package:flutter/services.dart';

import 'package:ezmoov_partner_app/models/booking_model.dart';

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

  late RideRequestViewModel viewModel;

  setUp(() {
    viewModel = RideRequestViewModel();
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('RideRequestViewModel Unit Tests', () {
    test('Haversine distance calculation produces correct kilometer output', () {
      // Bengaluru MG Road to Kempegowda Bus Station (approx 3.5 - 6.0 km)
      final dist = viewModel.calculateDistance(12.9756, 77.6066, 12.9779, 77.5727);
      expect(dist, greaterThan(3.5));
      expect(dist, lessThan(6.0));
    });

    test('Haversine distance returns 0.0 for zero coordinates', () {
      final dist = viewModel.calculateDistance(0.0, 0.0, 12.9756, 77.6066);
      expect(dist, equals(0.0));
    });

    test('declineRide adds bookingId to declined list and resets modal state', () {
      expect(viewModel.declinedBookingIds, isEmpty);

      viewModel.declineRide('test_booking_123');

      expect(viewModel.declinedBookingIds, contains('test_booking_123'));
      expect(viewModel.activeBroadcastBooking, isNull);
    });

    test('withdrawBid clears active pending bid state', () {
      viewModel.withdrawBid();
      expect(viewModel.hasPendingBid, isFalse);
      expect(viewModel.activePendingBidBooking, isNull);
      expect(viewModel.activePendingBid, isNull);
    });
  });

  group('Incoming Outstation Booking Eligibility Tests (40km & outstation_booking=true)', () {
    // Reference base driver location: MG Road Bengaluru (12.9756, 77.6066)
    const double driverLat = 12.9756;
    const double driverLng = 77.6066;

    // ~20 km away: Electronic City, Bengaluru (12.8399, 77.6770) -> distance approx 16.8 km (< 40 km)
    // ~55 km away: Ramanagara, Karnataka (12.7209, 77.2799) -> distance approx 45-50 km (> 40 km)

    BookingModel createOutstationBooking({
      required double pickupLat,
      required double pickupLng,
      String service = 'bidding_outstation',
    }) {
      return BookingModel(
        id: 'booking_outstation_test_1',
        customerId: 'cust_123',
        pickupAddress: 'Pickup Point',
        dropAddress: 'Drop Point (Intercity)',
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: 13.5000,
        dropLng: 78.5000,
        status: 'searching',
        service: service,
      );
    }

    test('Outstation booking WITHIN 40 km and outstation_booking=true is ELIGIBLE', () {
      final booking = createOutstationBooking(
        pickupLat: 12.8399,
        pickupLng: 77.6770, // ~17 km away
      );

      final isEligible = viewModel.isBookingEligibleForDriver(
        booking: booking,
        driverLat: driverLat,
        driverLng: driverLng,
        isOutstationBookingEnabled: true,
      );

      expect(isEligible, isTrue);
    });

    test('Outstation booking WITHIN 40 km but outstation_booking=false is INELIGIBLE', () {
      final booking = createOutstationBooking(
        pickupLat: 12.8399,
        pickupLng: 77.6770, // ~17 km away
      );

      final isEligible = viewModel.isBookingEligibleForDriver(
        booking: booking,
        driverLat: driverLat,
        driverLng: driverLng,
        isOutstationBookingEnabled: false,
      );

      expect(isEligible, isFalse);
    });

    test('Outstation booking EXCEEDING 40 km even if outstation_booking=true is INELIGIBLE', () {
      final booking = createOutstationBooking(
        pickupLat: 12.7209,
        pickupLng: 77.2799, // ~45+ km away
      );

      final dist = viewModel.calculateDistance(driverLat, driverLng, 12.7209, 77.2799);
      expect(dist, greaterThan(40.0));

      final isEligible = viewModel.isBookingEligibleForDriver(
        booking: booking,
        driverLat: driverLat,
        driverLng: driverLng,
        isOutstationBookingEnabled: true,
      );

      expect(isEligible, isFalse);
    });

    test('Outstation booking handles various service name representations ("outstation", "biddingoutstation")', () {
      final booking1 = createOutstationBooking(
        pickupLat: 12.8399,
        pickupLng: 77.6770,
        service: 'outstation',
      );
      final booking2 = createOutstationBooking(
        pickupLat: 12.8399,
        pickupLng: 77.6770,
        service: 'biddingoutstation',
      );

      expect(
        viewModel.isBookingEligibleForDriver(
          booking: booking1,
          driverLat: driverLat,
          driverLng: driverLng,
          isOutstationBookingEnabled: true,
        ),
        isTrue,
      );

      expect(
        viewModel.isBookingEligibleForDriver(
          booking: booking2,
          driverLat: driverLat,
          driverLng: driverLng,
          isOutstationBookingEnabled: false,
        ),
        isFalse,
      );
    });
  });

  group('Local Adda and Standard Services Distance Threshold Tests', () {
    const double driverLat = 12.9756;
    const double driverLng = 77.6066;

    test('Local Adda within 20.0 km is eligible, beyond 20.0 km is ineligible', () {
      // Near point ~15 km away (13.1000, 77.5946)
      final nearBooking = BookingModel(
        id: 'local_near',
        customerId: 'cust_1',
        pickupAddress: 'Nearby',
        dropAddress: 'Nearby Drop',
        pickupLat: 13.1000,
        pickupLng: 77.5946,
        dropLat: 12.9800,
        dropLng: 77.6200,
        status: 'searching',
        service: 'local_adda',
      );

      // Far point ~25.0 km away (13.2000, 77.5946)
      final farBooking = BookingModel(
        id: 'local_far',
        customerId: 'cust_2',
        pickupAddress: 'Far',
        dropAddress: 'Far Drop',
        pickupLat: 13.2000,
        pickupLng: 77.5946,
        dropLat: 12.9800,
        dropLng: 77.6200,
        status: 'searching',
        service: 'local_adda',
      );

      expect(
        viewModel.isBookingEligibleForDriver(
          booking: nearBooking,
          driverLat: driverLat,
          driverLng: driverLng,
        ),
        isTrue,
      );

      expect(
        viewModel.isBookingEligibleForDriver(
          booking: farBooking,
          driverLat: driverLat,
          driverLng: driverLng,
        ),
        isFalse,
      );
    });
  });
}
