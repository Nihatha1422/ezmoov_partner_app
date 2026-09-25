import 'package:flutter_test/flutter_test.dart';
import 'package:ezmoov_partner_app/models/vehicle_type_model.dart';

void main() {
  group('VehicleTypeModel Unit Tests', () {
    test('Parses vehicle type JSON payload correctly with millage_cost and outstation_charges', () {
      final json = {
        'id': 'v_type_3w',
        'name': '3 Wheeler',
        'capacity': '500 Kgs',
        'capacity_kg': 500.0,
        'base_fare': 210.0,
        'daily_fee': 150.0,
        'icon_name': 'electric_rickshaw',
        'is_active': true,
        'grace_time': 40,
        'waittime': 3.0,
        'millage_cost': 3.50,
        'outstation_charges': 27.00,
      };

      final vt = VehicleTypeModel.fromJson(json);

      expect(vt.id, equals('v_type_3w'));
      expect(vt.name, equals('3 Wheeler'));
      expect(vt.capacityKg, equals(500.0));
      expect(vt.baseFare, equals(210.0));
      expect(vt.dailyFee, equals(150.0));
      expect(vt.millageCost, equals(3.50));
      expect(vt.mileageCost, equals(3.50));
      expect(vt.outstationCharges, equals(27.00));
      expect(vt.isActive, isTrue);

      final outJson = vt.toJson();
      expect(outJson['millage_cost'], equals(3.50));
      expect(outJson['outstation_charges'], equals(27.00));
    });

    test('Parses all fleet vehicle types with respective millage_cost & outstation_charges', () {
      final listJson = [
        {
          'id': '3',
          'name': '3 Wheeler',
          'capacity': '500 Kgs',
          'capacity_kg': 500.0,
          'millage_cost': 3.5,
          'outstation_charges': 27.0,
        },
        {
          'id': '4',
          'name': '4 Wheeler (Tata Ace)',
          'capacity': '750 Kgs',
          'capacity_kg': 750.0,
          'millage_cost': 4.0,
          'outstation_charges': 35.50,
        },
        {
          'id': '5',
          'name': '4 Wheeler (8ft)',
          'capacity': '1200 Kgs',
          'capacity_kg': 1200.0,
          'millage_cost': 7.0,
          'outstation_charges': 35.71,
        },
        {
          'id': '6',
          'name': '4 Wheeler (9ft)',
          'capacity': '1700 Kgs',
          'capacity_kg': 1700.0,
          'millage_cost': 7.0,
          'outstation_charges': 42.90,
        },
        {
          'id': '7',
          'name': '4 Wheeler (10ft)',
          'capacity': '2000 Kgs',
          'capacity_kg': 2000.0,
          'millage_cost': 7.0,
          'outstation_charges': 45.00,
        },
      ];

      final types = listJson.map((j) => VehicleTypeModel.fromJson(j)).toList();
      expect(types, hasLength(5));

      final threeWheeler = types.firstWhere((vt) => vt.id == '3');
      expect(threeWheeler.millageCost, equals(3.5));
      expect(threeWheeler.outstationCharges, equals(27.0));

      final tataAce = types.firstWhere((vt) => vt.id == '4');
      expect(tataAce.millageCost, equals(4.0));
      expect(tataAce.outstationCharges, equals(35.50));

      final eightFt = types.firstWhere((vt) => vt.id == '5');
      expect(eightFt.millageCost, equals(7.0));
      expect(eightFt.outstationCharges, equals(35.71));

      final nineFt = types.firstWhere((vt) => vt.id == '6');
      expect(nineFt.millageCost, equals(7.0));
      expect(nineFt.outstationCharges, equals(42.90));

      final tenFt = types.firstWhere((vt) => vt.id == '7');
      expect(tenFt.millageCost, equals(7.0));
      expect(tenFt.outstationCharges, equals(45.00));
    });
  });
}
