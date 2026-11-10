import 'misamis_occidental_address_catalog.dart';

/// Philippine address hierarchy for Misamis Occidental (PSGC-based).
class MisamisOccidentalAddressData {
  MisamisOccidentalAddressData._({required this.cities});

  static const provinceName = 'Misamis Occidental';
  static const countryName = 'Philippines';

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
    required String street,
    required String barangay,
    required String city,
  }) {
    final parts = <String>[
      street.trim(),
      barangay.trim(),
      city.trim(),
      provinceName,
      countryName,
    ];
    return parts.where((part) => part.isNotEmpty).join(', ');
  }
}
