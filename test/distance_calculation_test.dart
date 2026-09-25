import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezmoov_partner_app/core/services/google_directions_service.dart';
import 'package:ezmoov_partner_app/models/booking_model.dart';
import 'package:ezmoov_partner_app/models/intermediate_stop_model.dart';
import 'package:ezmoov_partner_app/viewmodels/ride_request_viewmodel.dart';
import 'package:ezmoov_partner_app/widgets/route_location_tile.dart';

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

  group('GoogleDirectionsService & Parity Distance Calculation Tests', () {
    // Exact reference formula from customer app / prompt:
    double referenceHaversineDistance(
        double lat1, double lon1, double lat2, double lon2) {
      const double p = 0.017453292519943295;
      final double a = 0.5 -
          math.cos((lat2 - lat1) * p) / 2 +
          math.cos(lat1 * p) *
              math.cos(lat2 * p) *
              (1 - math.cos((lon2 - lon1) * p)) /
              2;
      final double km = 12742 * math.asin(math.sqrt(a));
      return km;
    }

    test('calculateHaversineDistance matches reference formula exactly', () {
      const lat1 = 17.440081;
      const lon1 = 78.348915;
      const lat2 = 17.448293;
      const lon2 = 78.374238;

      final expectedKm = referenceHaversineDistance(lat1, lon1, lat2, lon2);
      final actualKm =
          GoogleDirectionsService.calculateHaversineDistance(lat1, lon1, lat2, lon2);

      expect(actualKm, closeTo(expectedKm, 0.0001));
    });

    test('calculateSegmentDistance multiplies Haversine by 1.3x and rounds to 1 decimal place', () {
      const lat1 = 17.440081;
      const lon1 = 78.348915;
      const lat2 = 17.448293;
      const lon2 = 78.374238;

      final straight = referenceHaversineDistance(lat1, lon1, lat2, lon2);
      final expectedSegment = double.parse((straight * 1.3).toStringAsFixed(1));

      final actualSegment =
          GoogleDirectionsService.calculateSegmentDistance(lat1, lon1, lat2, lon2);

      expect(actualSegment, equals(expectedSegment));
    });

    test('calculateSegmentDistance returns fallbackKm for 0.0 coordinates', () {
      final fallback = GoogleDirectionsService.calculateSegmentDistance(0.0, 0.0, 0.0, 0.0);
      expect(fallback, equals(2.5));
    });

    test('calculateRouteDistance computes multi-stop trip with 1.3x road factor', () {
      // Pickup -> Stop 1 -> Stop 2 -> Drop
      const pickupLat = 17.440081;
      const pickupLng = 78.348915;
      const stop1Lat = 17.445100;
      const stop1Lng = 78.360200;
      const stop2Lat = 17.448293;
      const stop2Lng = 78.374238;
      const dropLat = 17.460100;
      const dropLng = 78.390500;

      final stops = [
        IntermediateStopModel(latitude: stop1Lat, longitude: stop1Lng, address: 'Stop 1'),
        IntermediateStopModel(latitude: stop2Lat, longitude: stop2Lng, address: 'Stop 2'),
      ];

      final leg1 = referenceHaversineDistance(pickupLat, pickupLng, stop1Lat, stop1Lng);
      final leg2 = referenceHaversineDistance(stop1Lat, stop1Lng, stop2Lat, stop2Lng);
      final leg3 = referenceHaversineDistance(stop2Lat, stop2Lng, dropLat, dropLng);
      final totalStraight = leg1 + leg2 + leg3;
      final expectedTotal = double.parse((totalStraight * 1.3).toStringAsFixed(1));

      final actualTotal = GoogleDirectionsService.calculateRouteDistance(
        startLat: pickupLat,
        startLng: pickupLng,
        endLat: dropLat,
        endLng: dropLng,
        stops: stops,
      );

      expect(actualTotal, equals(expectedTotal));
      expect(actualTotal, greaterThan(0.0));
    });

    test('calculateRouteDistance returns fallbackKm when coordinates are missing/zero', () {
      final fallback = GoogleDirectionsService.calculateRouteDistance(
        startLat: 0.0,
        startLng: 0.0,
        endLat: 0.0,
        endLng: 0.0,
      );
      expect(fallback, equals(12.4));
    });
  });

  group('RideRequestViewModel Trip Distance & Realtime Integration', () {
    late RideRequestViewModel viewModel;

    setUp(() {
      viewModel = RideRequestViewModel();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('calculateTripDistance computes correct route distance for BookingModel with stops', () {
      final booking = BookingModel.fromJson({
        'id': 'booking_trip_test',
        'customer_id': 'cust_001',
        'pickup_address': 'Gachibowli',
        'drop_address': 'Madhapur',
        'pickup_lat': 17.4400,
        'pickup_lng': 78.3489,
        'drop_lat': 17.4600,
        'drop_lng': 78.3900,
        'status': 'searching',
        'intermediate_stops': [
          {'latitude': 17.4450, 'longitude': 78.3600, 'address': 'Hitec City'},
        ],
        'amount': {'total_price': 180.0},
      });

      final tripDist = viewModel.calculateTripDistance(booking);
      expect(tripDist, greaterThan(0.0));

      final expected = GoogleDirectionsService.calculateRouteDistance(
        startLat: booking.pickupLat,
        startLng: booking.pickupLng,
        endLat: booking.dropLat,
        endLng: booking.dropLng,
        stops: booking.effectiveIntermediateStops,
      );
      expect(tripDist, equals(expected));
    });

    test('calculateTripDistance uses cached road distance if available', () {
      final booking = BookingModel.fromJson({
        'id': 'booking_cached',
        'customer_id': 'cust_002',
        'pickup_address': 'Origin',
        'drop_address': 'Destination',
        'pickup_lat': 17.4400,
        'pickup_lng': 78.3489,
        'drop_lat': 17.4600,
        'drop_lng': 78.3900,
        'status': 'searching',
        'amount': {'total_price': 150.0},
      });

      // Initially fallback/Haversine
      final initialDist = viewModel.calculateTripDistance(booking);
      expect(initialDist, greaterThan(0.0));

      // Simulate cached road distance update (e.g. from Google Directions API)
      viewModel.setCachedRoadDistance('booking_cached', 15.8);

      final updatedDist = viewModel.calculateTripDistance(booking);
      expect(updatedDist, equals(15.8));
    });

    test('calculateSegmentDistance handles previous waypoint to current stop calculation', () {
      final segmentDist = viewModel.calculateSegmentDistance(
        17.4400, 78.3489,
        17.4450, 78.3600,
      );
      expect(segmentDist, greaterThan(0.0));
      expect(segmentDist.toString(), matches(r'^\d+\.\d$'));
    });
  });

  group('RouteLocationTile Widget Display Tests', () {
    testWidgets('RouteLocationTile displays distance badge with KM', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RouteLocationTile(
              type: LocationTileType.stop,
              address: 'Intermediate Stop A',
              distanceKm: 3.4,
              stopIndex: 1,
            ),
          ),
        ),
      );

      expect(find.text('INTERMEDIATE STOP A'), findsOneWidget);
      expect(find.text('3.4 KM'), findsOneWidget);
    });

    testWidgets('RouteLocationTile supports customDistanceText', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RouteLocationTile(
              type: LocationTileType.drop,
              address: 'Final Drop Destination',
              distanceKm: 14.2,
              customDistanceText: '14.2 KM total',
            ),
          ),
        ),
      );

      expect(find.text('Final Drop Destination'), findsOneWidget);
      expect(find.text('14.2 KM total'), findsOneWidget);
    });
  });
}
