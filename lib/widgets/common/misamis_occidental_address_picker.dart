import 'package:flutter/material.dart';

import '../../data/misamis_occidental_address_data.dart';
import '../../theme/app_theme.dart';

/// Cascading address fields limited to Misamis Occidental, Philippines.
class MisamisOccidentalAddressPicker extends StatefulWidget {
  const MisamisOccidentalAddressPicker({
    super.key,
    required this.onChanged,
    this.validator,
    this.formFieldKey,
  });

  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;
  final GlobalKey<FormFieldState<String>>? formFieldKey;

  @override
  State<MisamisOccidentalAddressPicker> createState() =>
      _MisamisOccidentalAddressPickerState();
}

class _MisamisOccidentalAddressPickerState
    extends State<MisamisOccidentalAddressPicker> {
  late final MisamisOccidentalAddressData _data =
      MisamisOccidentalAddressData.cached;

  String? _purok;
  String? _city;
  String? _barangay;

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppTheme.cleanWhite,
      border: const OutlineInputBorder(),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
    String? hint,
  }) {
    return DropdownButtonFormField<String>(
      value: value != null && items.contains(value) ? value : null,
      decoration: _decoration(label, hint: hint),
      isExpanded: true,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final barangays = _data.barangaysFor(_city);

    return FormField<String>(
      key: widget.formFieldKey,
      initialValue: '',
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) {
        void updateField() {
          final composed = _composedAddress();
          field.didChange(composed);
          widget.onChanged(composed);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Address (Misamis Occidental only)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            _dropdown(
              label: 'Purok *',
              value: _purok,
              items: MisamisOccidentalAddressData.purokOptions,
              hint: 'Select purok',
              onChanged: (value) {
                setState(() => _purok = value);
                updateField();
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'City / Municipality *',
              value: _city,
              items: _data.cityNames,
              hint: 'Select city or municipality',
              onChanged: (value) {
                setState(() {
                  _city = value;
                  _barangay = null;
                });
                updateField();
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Barangay *',
              value: _barangay,
              items: barangays,
              hint: _city == null ? 'Select city first' : 'Select barangay',
              onChanged: _city == null
                  ? null
                  : (value) {
                      setState(() => _barangay = value);
                      updateField();
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              readOnly: true,
              initialValue: MisamisOccidentalAddressData.provinceName,
              decoration: _decoration('Province'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              readOnly: true,
              initialValue: MisamisOccidentalAddressData.countryName,
              decoration: _decoration('Country'),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _composedAddress() {
    if (_purok == null || _barangay == null || _city == null) return '';
    return MisamisOccidentalAddressData.compose(
      purok: _purok!,
      barangay: _barangay!,
      city: _city!,
    );
  }
}
