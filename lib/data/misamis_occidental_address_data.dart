import 'misamis_occidental_address_catalog.dart';

/// Philippine address hierarchy for Misamis Occidental (PSGC-based).
class MisamisOccidentalAddressData {
  MisamisOccidentalAddressData._({required this.cities});

  static const provinceName = 'Misamis Occidental';
  static const countryName = 'Philippines';

  static const purokOptions = <String>[
    'Purok 1',
    'Purok 2',
    'Purok 3',
    'Purok 4',
    'Purok 5',
    'Purok 6',
    'Purok 7',
  ];

  final Map<String, List<String>> cities;

  static MisamisOccidentalAddressData? _cache;

  static MisamisOccidentalAddressData get cached {
    return _cache ??= MisamisOccidentalAddressData._(
      cities: misamisOccidentalAddressCatalog,
    );
  }

  static Future<MisamisOccidentalAddressData> load() async => cached;

  List<String> get cityNames => cities.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  List<String> barangaysFor(String? city) {
    if (city == null || city.isEmpty) return const [];
    return cities[city] ?? const [];
  }

  static String compose({
    required String purok,
    required String barangay,
    required String city,
  }) {
    final parts = <String>[
      purok.trim(),
      barangay.trim(),
      city.trim(),
      provinceName,
      countryName,
    ];
    return parts.join(', ');
  }
}
