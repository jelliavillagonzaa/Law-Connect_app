import 'package:flutter/material.dart';

import '../../data/misamis_occidental_address_data.dart';
import '../../theme/app_theme.dart';

/// Street line plus Misamis Occidental city and barangay.
///
/// [streetController], [city], and [barangay] are owned by the parent so the
/// values survive when this step is hidden.
class MisamisOccidentalAddressPicker extends StatelessWidget {
  const MisamisOccidentalAddressPicker({
    super.key,
    required this.streetController,
    required this.city,
    required this.barangay,
    required this.onCityChanged,
    required this.onBarangayChanged,
    required this.onStreetChanged,
    this.placeError,
  });

  final TextEditingController streetController;
  final String? city;
  final String? barangay;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<String?> onBarangayChanged;
  final VoidCallback onStreetChanged;
  final String? placeError;

  @override
  Widget build(BuildContext context) {
    final data = MisamisOccidentalAddressData.cached;
    final barangays = data.barangaysFor(city);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Address in Misamis Occidental',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: streetController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'Street address *',
            hint: 'House no., Street, Purok, or Sitio',
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) {
              return 'Enter your street, purok, or sitio';
            }
            if (trimmed.length < 2) {
              return 'Street address is too short';
            }
            return null;
          },
          onChanged: (_) => onStreetChanged(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: city != null && data.cityNames.contains(city)
              ? city
              : null,
          decoration: _decoration(
            'City / Municipality *',
            hint: 'Select city or municipality',
          ),
          isExpanded: true,
          items: data.cityNames
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onCityChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('barangay-$city'),
          initialValue:
              barangay != null && barangays.contains(barangay) ? barangay : null,
          decoration: _decoration(
            'Barangay *',
            hint: city == null ? 'Select city first' : 'Select barangay',
          ),
          isExpanded: true,
          items: barangays
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: city == null ? null : onBarangayChanged,
        ),
        if (placeError != null) ...[
          const SizedBox(height: 8),
          Text(
            placeError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _lockedLine('Province', MisamisOccidentalAddressData.provinceName),
        const SizedBox(height: 12),
        _lockedLine('Country', MisamisOccidentalAddressData.countryName),
      ],
    );
  }

  Widget _lockedLine(String label, String value) {
    return InputDecorator(
      decoration: _decoration(label),
      child: Text(value),
    );
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppTheme.cleanWhite,
      border: const OutlineInputBorder(),
    );
  }
}
