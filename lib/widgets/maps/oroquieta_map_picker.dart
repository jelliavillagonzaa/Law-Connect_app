import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:permission_handler/permission_handler.dart';

/// Result class to return coordinates and address
class MapPickerResult {
  final double latitude;
  final double longitude;
  final String? address;

  MapPickerResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });
}

/// Map picker centered on Oroquieta City using OpenStreetMap (no API key).
class OroquietaMapPicker extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const OroquietaMapPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<OroquietaMapPicker> createState() => _OroquietaMapPickerState();
}

class _OroquietaMapPickerState extends State<OroquietaMapPicker> {
  static const double _oroquietaLat = 8.4885;
  static const double _oroquietaLng = 123.8047;
  static const double _minZoom = 13.0;
  static const double _maxZoom = 19.0;
  static const Color _primaryBlue = Color(0xFF1A3A6C);
  static const String _nominatimUserAgent =
      'LawConnect/1.0 (law-connect-app)';

  static const double _boundsSouth = 8.4400;
  static const double _boundsNorth = 8.5400;
  static const double _boundsWest = 123.7600;
  static const double _boundsEast = 123.8500;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  latlong.LatLng _selectedPosition =
      latlong.LatLng(_oroquietaLat, _oroquietaLng);
  String? _selectedAddress;
  bool _isLoadingAddress = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _placeSuggestions = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPosition = latlong.LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
    }
    _loadAddressFor(_selectedPosition);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() => _placeSuggestions = []);
      return;
    }
    _searchPlaces(query);
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _isSearching = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent('$query, Oroquieta City, Philippines')}'
        '&format=json&limit=5&countrycodes=ph',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': _nominatimUserAgent},
      );
      if (response.statusCode == 200 && mounted) {
        final results = json.decode(response.body) as List;
        setState(() {
          _placeSuggestions = results
              .where((item) {
                final name =
                    (item['display_name'] as String? ?? '').toLowerCase();
                return name.contains('oroquieta') ||
                    name.contains('poblacion');
              })
              .map((item) {
                return {
                  'lat': double.parse(item['lat'].toString()),
                  'lon': double.parse(item['lon'].toString()),
                  'display_name': item['display_name'] as String? ?? '',
                };
              })
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _placeSuggestions = []);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final position =
        latlong.LatLng(place['lat'] as double, place['lon'] as double);
    if (!_isWithinBounds(position)) {
      _showSnack(
        'This location is outside Oroquieta City.',
        Colors.orange,
      );
      return;
    }
    _mapController.move(position, 16);
    setState(() {
      _selectedPosition = position;
      _selectedAddress = place['display_name'] as String?;
      _placeSuggestions = [];
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  bool _isWithinBounds(latlong.LatLng position) {
    return position.latitude >= _boundsSouth &&
        position.latitude <= _boundsNorth &&
        position.longitude >= _boundsWest &&
        position.longitude <= _boundsEast;
  }

  void _updateSelection(latlong.LatLng position) {
    if (!_isWithinBounds(position)) {
      _showSnack(
        'Please select a location within Oroquieta City only.',
        Colors.orange,
      );
      return;
    }
    setState(() => _selectedPosition = position);
    _loadAddressFor(position);
  }

  Future<void> _loadAddressFor(latlong.LatLng position) async {
    setState(() => _isLoadingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${position.latitude}&lon=${position.longitude}&format=json',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': _nominatimUserAgent},
      );
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final name = data['display_name'] as String?;
        setState(() {
          _selectedAddress = name?.isNotEmpty == true
              ? name
              : 'Oroquieta City';
          _isLoadingAddress = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _selectedAddress = 'Oroquieta City';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        _showSnack(
          'Location permission is required to use your current location.',
          Colors.orange,
        );
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('Please enable location services.', Colors.orange);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = latlong.LatLng(position.latitude, position.longitude);
      if (!_isWithinBounds(latLng)) {
        _showSnack(
          'Your location is outside Oroquieta City.',
          Colors.orange,
        );
        return;
      }
      _mapController.move(
        latLng,
        _mapController.camera.zoom.clamp(_minZoom, _maxZoom),
      );
      _updateSelection(latLng);
    } catch (e) {
      _showSnack('Error getting location: $e', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _confirmLocation() {
    Navigator.pop(
      context,
      MapPickerResult(
        latitude: _selectedPosition.latitude,
        longitude: _selectedPosition.longitude,
        address: _selectedAddress,
      ),
    );
  }

  void _zoomIn() {
    final zoom = (_mapController.camera.zoom + 1).clamp(_minZoom, _maxZoom);
    _mapController.move(_mapController.camera.center, zoom);
  }

  void _zoomOut() {
    final zoom = (_mapController.camera.zoom - 1).clamp(_minZoom, _maxZoom);
    _mapController.move(_mapController.camera.center, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Select Location',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPosition,
              initialZoom: 15,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onTap: (_, point) => _updateSelection(
                latlong.LatLng(point.latitude, point.longitude),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lawconnect.app',
                maxZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: latlong.LatLng(_oroquietaLat, _oroquietaLng),
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: 36,
                    ),
                  ),
                  Marker(
                    point: _selectedPosition,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: isDesktop ? 16 : 12,
            left: isDesktop ? 16 : 12,
            right: isDesktop ? 72 : 68,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search places in Oroquieta City...',
                  prefixIcon: const Icon(Icons.search, color: _primaryBlue),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _placeSuggestions = []);
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          if (_placeSuggestions.isNotEmpty)
            Positioned(
              top: isDesktop ? 68 : 64,
              left: isDesktop ? 16 : 12,
              right: isDesktop ? 72 : 68,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _placeSuggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _placeSuggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.location_on,
                          color: _primaryBlue,
                        ),
                        title: Text(
                          place['display_name'] as String? ?? '',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  ),
                ),
              ),
            ),
          Positioned(
            top: _placeSuggestions.isNotEmpty
                ? (isDesktop ? 300 : 290)
                : (isDesktop ? 68 : 64),
            left: isDesktop ? 16 : 12,
            right: isDesktop ? 72 : 68,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.95),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: _primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _isLoadingAddress
                          ? Text(
                              'Loading address...',
                              style: TextStyle(
                                fontSize: isDesktop ? 14 : 12,
                                color: Colors.grey[600],
                              ),
                            )
                          : Text(
                              _selectedAddress ??
                                  'Tap on map to select location',
                              style: TextStyle(
                                fontSize: isDesktop ? 14 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: isDesktop ? 16 : 12,
            right: isDesktop ? 16 : 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  onPressed: _useMyLocation,
                  backgroundColor: Colors.white,
                  foregroundColor: _primaryBlue,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _zoomIn,
                        tooltip: 'Zoom in',
                      ),
                      Container(height: 1, width: 40, color: Colors.grey[300]),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _zoomOut,
                        tooltip: 'Zoom out',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: isDesktop ? 24 : 16,
            left: isDesktop ? 24 : 16,
            right: isDesktop ? 24 : 16,
            child: ElevatedButton.icon(
              onPressed: _confirmLocation,
              icon: const Icon(Icons.check_circle),
              label: Text(
                'Confirm Location',
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: isDesktop ? 16 : 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to convert coordinates to readable address
Future<String> convertCoordinatesToAddress(double lat, double lng) async {
  try {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json',
    );
    final response = await http.get(
      url,
      headers: {'User-Agent': 'LawConnect/1.0 (law-connect-app)'},
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final displayName = data['display_name'] as String?;
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
    }
  } catch (_) {}
  return 'Oroquieta City';
}
