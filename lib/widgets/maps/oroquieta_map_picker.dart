import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

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

/// A reusable Google Maps picker widget centered on Oroquieta City
/// Allows users to drop a marker and select coordinates
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
  // Oroquieta City coordinates (default center)
  static const double _oroquietaLat = 8.4885;
  static const double _oroquietaLng = 123.8047;
  static const double _minZoom = 14.0; // Increased minimum zoom to prevent viewing outside areas
  static const double _maxZoom = 18.0;
  
  // Poblacion 1, Oroquieta City coordinates (main location marker)
  static const double _poblacion1Lat = 8.4885;
  static const double _poblacion1Lng = 123.8047;
  
  // Oroquieta City boundaries (bounds to restrict map view)
  // Boundaries to include all barangays of Oroquieta City including Poblacion 1
  // Approximate boundaries of Oroquieta City, Misamis Occidental
  static final LatLngBounds _oroquietaBounds = LatLngBounds(
    southwest: const LatLng(8.4400, 123.7600), // Southwest corner - includes all barangays
    northeast: const LatLng(8.5400, 123.8500), // Northeast corner - includes all barangays
  );

  // Color constants
  static const Color primaryRed = Color(0xFF1A4D8F); // Royal Blue

  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  Marker? _marker;
  Marker? _poblacion1Marker; // Poblacion 1 location marker
  String? _selectedAddress;
  bool _isLoadingAddress = false;
  double _currentZoom = 15.0;

  // Places search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _placeSuggestions = [];
  bool _isSearching = false;
  bool _showSuggestions = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // Google Places API - Note: You need to add your API key
  // For production, store this in environment variables or secure storage
  static const String _placesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';

  @override
  void initState() {
    super.initState();
    
    // Create Poblacion 1 location marker FIRST (always visible)
    _createPoblacion1Marker();
    
    // Initialize with provided coordinates or Oroquieta center
    _selectedPosition =
        widget.initialLatitude != null && widget.initialLongitude != null
        ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
        : const LatLng(_oroquietaLat, _oroquietaLng);
    
    // Create initial marker
    _updateMarker(_selectedPosition!);
    // Get address for initial position
    _getAddressFromCoordinates(
      _selectedPosition!.latitude,
      _selectedPosition!.longitude,
    );

    // Setup search controller listener
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeOverlay();
    _mapController?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _placeSuggestions = [];
        _showSuggestions = false;
      });
      _removeOverlay();
      return;
    }

    if (query.length >= 2) {
      _searchPlaces(query);
    }
  }

  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus && _placeSuggestions.isNotEmpty) {
      _showSuggestionsOverlay();
    } else if (!_searchFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_searchFocusNode.hasFocus && mounted) {
          _removeOverlay();
        }
      });
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (_placesApiKey == 'YOUR_GOOGLE_PLACES_API_KEY') {
      // API key not configured - show message or use fallback
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Restrict search to Oroquieta City using strict bounds
      // Using rectangular bounds to restrict to Oroquieta City only
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=$_placesApiKey'
        '&location=${_oroquietaLat},${_oroquietaLng}'
        '&radius=3000' // 3km radius around Oroquieta City center (very restrictive - barangays only)
        '&components=country:ph|locality:Oroquieta' // Restrict to Oroquieta City specifically
        '&strictbounds=true' // Strictly restrict results to within bounds
        '&language=en',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = data['predictions'] as List;

          // Filter to only show results that mention Oroquieta City or its barangays
          // This includes Poblacion 1 and all other barangays within Oroquieta City
          final filtered = predictions.where((prediction) {
            final description = (prediction['description'] as String)
                .toLowerCase();
            // Show results that contain "oroquieta" (city name)
            // This includes Poblacion 1, Poblacion 2, and all other barangays
            return description.contains('oroquieta') || 
                   description.contains('poblacion');
          }).toList();
          
          // Additional validation: check if coordinates are within bounds
          // This will be done when place is selected

          if (mounted) {
            setState(() {
              _placeSuggestions = filtered.map((prediction) {
                return {
                  'place_id': prediction['place_id'],
                  'description': prediction['description'],
                  'main_text':
                      prediction['structured_formatting']?['main_text'] ?? '',
                  'secondary_text':
                      prediction['structured_formatting']?['secondary_text'] ??
                      '',
                };
              }).toList();
              _showSuggestions = _placeSuggestions.isNotEmpty;
            });

            if (_searchFocusNode.hasFocus && _showSuggestions) {
              _showSuggestionsOverlay();
            }
          }
        }
      }
    } catch (e) {
      // Handle error silently or show message
      if (mounted) {
        setState(() {
          _placeSuggestions = [];
          _showSuggestions = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    if (_placesApiKey == 'YOUR_GOOGLE_PLACES_API_KEY') {
      return;
    }

    try {
      // Get place details
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${place['place_id']}'
        '&key=$_placesApiKey'
        '&fields=geometry,formatted_address,name',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];
          final location = result['geometry']?['location'];

          if (location != null) {
            final lat = location['lat'] as double;
            final lng = location['lng'] as double;
            final address =
                result['formatted_address'] as String? ?? place['description'];

            final newPosition = LatLng(lat, lng);
            
            // Check if selected place is within Oroquieta City bounds
            if (!_isWithinOroquietaBounds(newPosition)) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This location is outside Oroquieta City. Please select a location within Oroquieta City only.',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              return;
            }

            // Move camera to selected place
            if (_mapController != null) {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(newPosition, 16.0),
              );
            }

            // Update marker and address
            _updateMarker(newPosition);
            setState(() {
              _selectedAddress = address;
            });

            // Clear search
            _searchController.clear();
            _searchFocusNode.unfocus();
            _removeOverlay();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading place details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSuggestionsOverlay() {
    _removeOverlay();

    if (!_showSuggestions || _placeSuggestions.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width:
            MediaQuery.of(context).size.width -
            (MediaQuery.of(context).size.width >= 800 ? 40 : 32),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _placeSuggestions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final place = _placeSuggestions[index];
                  return ListTile(
                    leading: Icon(Icons.location_on, color: primaryRed),
                    title: Text(
                      place['main_text'] ?? place['description'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle:
                        place['secondary_text'] != null &&
                            place['secondary_text'].toString().isNotEmpty
                        ? Text(
                            place['secondary_text'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          )
                        : null,
                    onTap: () => _selectPlace(place),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Creates a permanent marker for Poblacion 1, Oroquieta City
  void _createPoblacion1Marker() {
    _poblacion1Marker = Marker(
      markerId: const MarkerId('poblacion1_location'),
      position: const LatLng(_poblacion1Lat, _poblacion1Lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(
        title: 'Poblacion 1',
        snippet: 'Oroquieta City, 7207, Philippines',
      ),
      anchor: const Offset(0.5, 1.0), // Pin point at the bottom
      draggable: false, // Not draggable - permanent location
      consumeTapEvents: true, // Allow tap to show info window
    );
    
    if (mounted) {
      setState(() {});
    }
  }

  void _updateMarker(LatLng position) {
    // Validate position is within bounds before updating
    if (!_isWithinOroquietaBounds(position)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location must be within Oroquieta City. Marker reset to center.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Reset to center of Oroquieta City
      position = const LatLng(_oroquietaLat, _oroquietaLng);
    }
    
    setState(() {
      _selectedPosition = position;
      _marker = Marker(
        markerId: const MarkerId('selected_location'),
        position: position,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        onDragEnd: (newPosition) {
          // Check if dragged position is within bounds
          if (!_isWithinOroquietaBounds(newPosition)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Location must be within Oroquieta City. Marker reset.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            }
            // Reset marker to previous valid position
            _updateMarker(_selectedPosition ?? const LatLng(_oroquietaLat, _oroquietaLng));
            return;
          }
          _selectedPosition = newPosition;
          _getAddressFromCoordinates(
            newPosition.latitude,
            newPosition.longitude,
          );
        },
      );
    });
  }

  Future<void> _getAddressFromCoordinates(double lat, double lng) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        // Format address for Oroquieta
        String address = '';
        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.subLocality!;
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.locality!;
        }
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.administrativeArea!;
        }
        if (place.country != null && place.country!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.country!;
        }

        setState(() {
          _selectedAddress = address.isNotEmpty ? address : 'Oroquieta City';
          _isLoadingAddress = false;
        });
      } else {
        setState(() {
          _selectedAddress = 'Oroquieta City';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      setState(() {
        _selectedAddress = 'Oroquieta City';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    try {
      // Request location permission
      PermissionStatus status = await Permission.location.request();

      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required to use your current location',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable location services'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPosition = LatLng(position.latitude, position.longitude);
      
      // Check if user is within Oroquieta City bounds
      if (!_isWithinOroquietaBounds(newPosition)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your location is outside Oroquieta City. Please select a location within Oroquieta City.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Move camera to user location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(newPosition, _currentZoom),
        );
      }

      // Update marker
      _updateMarker(newPosition);
      _getAddressFromCoordinates(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onMapTap(LatLng position) {
    // Check if tapped location is within Oroquieta City bounds
    if (!_isWithinOroquietaBounds(position)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select a location within Oroquieta City only.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    _updateMarker(position);
    _getAddressFromCoordinates(position.latitude, position.longitude);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Immediately restrict camera to Oroquieta City bounds
    Future.delayed(const Duration(milliseconds: 100), () {
      _restrictCameraToBounds();
    });
  }

  void _onCameraMove(CameraPosition position) {
    _currentZoom = position.zoom;
    // Aggressively check and restrict camera movement
    _restrictCameraToBounds();
  }
  
  /// Restricts the camera to stay within Oroquieta City bounds
  Future<void> _restrictCameraToBounds() async {
    if (_mapController == null) return;
    
    try {
      final currentPosition = await _mapController!.getVisibleRegion();
      
      // Check if camera is outside bounds
      bool needsRestriction = false;
      double targetLat = _oroquietaLat;
      double targetLng = _oroquietaLng;
      double targetZoom = _currentZoom;
      
      // Check if current camera position is outside bounds
      if (currentPosition.northeast.latitude > _oroquietaBounds.northeast.latitude ||
          currentPosition.northeast.longitude > _oroquietaBounds.northeast.longitude ||
          currentPosition.southwest.latitude < _oroquietaBounds.southwest.latitude ||
          currentPosition.southwest.longitude < _oroquietaBounds.southwest.longitude) {
        needsRestriction = true;
      }
      
      // Also check if zoom is too low (showing too much area)
      if (_currentZoom < _minZoom) {
        needsRestriction = true;
        targetZoom = _minZoom;
      }
      
      if (needsRestriction) {
        // Calculate center of visible region if it's within bounds, otherwise use Oroquieta center
        final centerLat = (currentPosition.northeast.latitude + currentPosition.southwest.latitude) / 2;
        final centerLng = (currentPosition.northeast.longitude + currentPosition.southwest.longitude) / 2;
        
        // Check if center is within bounds
        if (_isWithinOroquietaBounds(LatLng(centerLat, centerLng))) {
          targetLat = centerLat;
          targetLng = centerLng;
        }
        
        // Move camera back to valid position
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(targetLat, targetLng),
            targetZoom.clamp(_minZoom, _maxZoom),
          ),
        );
      }
    } catch (e) {
      // Handle error silently
    }
  }
  
  /// Checks if a location is within Oroquieta City bounds
  bool _isWithinOroquietaBounds(LatLng position) {
    return _oroquietaBounds.contains(position);
  }

  void _confirmLocation() {
    if (_selectedPosition != null) {
      Navigator.pop(
        context,
        MapPickerResult(
          latitude: _selectedPosition!.latitude,
          longitude: _selectedPosition!.longitude,
          address: _selectedAddress,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        title: Text(
          'Select Location',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target:
                  _selectedPosition ??
                  const LatLng(_oroquietaLat, _oroquietaLng),
              zoom: _currentZoom.clamp(_minZoom, _maxZoom),
            ),
            markers: <Marker>{
              // Always show Poblacion 1 marker
              if (_poblacion1Marker != null) _poblacion1Marker!,
              // Show user-selected marker if exists
              if (_marker != null) _marker!,
            },
            onTap: _onMapTap,
            onCameraMove: _onCameraMove,
            minMaxZoomPreference: const MinMaxZoomPreference(
              _minZoom,
              _maxZoom,
            ),
            cameraTargetBounds: CameraTargetBounds(_oroquietaBounds),
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
          ),

          // Use My Location Button (Top Right)
          Positioned(
            top: isDesktop ? 20 : 16,
            right: isDesktop ? 20 : 16,
            child: FloatingActionButton(
              onPressed: _useMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: primaryRed,
              elevation: 4,
              child: const Icon(Icons.my_location),
            ),
          ),

          // Google Places Search Bar (Top Center)
          Positioned(
            top: isDesktop ? 20 : 16,
            left: isDesktop ? 20 : 16,
            right: isDesktop ? 20 : 16,
            child: CompositedTransformTarget(
              link: _layerLink,
              child: Container(
                margin: EdgeInsets.only(right: isDesktop ? 80 : 76),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search places in Oroquieta City...',
                    hintStyle: TextStyle(
                      fontSize: isDesktop ? 14 : 12,
                      color: Colors.grey[500],
                    ),
                    prefixIcon: Icon(Icons.search, color: primaryRed),
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
                              _removeOverlay();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 16 : 12,
                      vertical: isDesktop ? 14 : 12,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                  onTap: () {
                    if (_placeSuggestions.isNotEmpty) {
                      _showSuggestionsOverlay();
                    }
                  },
                ),
              ),
            ),
          ),

          // Address Display (Below Search Bar)
          Positioned(
            top: isDesktop ? 90 : 80,
            left: isDesktop ? 20 : 16,
            right: isDesktop ? 20 : 16,
            child: Container(
              margin: EdgeInsets.only(right: isDesktop ? 80 : 76),
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 16 : 12,
                vertical: isDesktop ? 12 : 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: primaryRed, size: 20),
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
                            _selectedAddress ?? 'Tap on map to select location',
                            style: TextStyle(
                              fontSize: isDesktop ? 14 : 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Confirm Location Button (Bottom)
          Positioned(
            bottom: isDesktop ? 40 : 24,
            left: isDesktop ? 40 : 24,
            right: isDesktop ? 40 : 24,
            child: ElevatedButton(
              onPressed: _confirmLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 32 : 24,
                  vertical: isDesktop ? 18 : 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Confirm Location',
                    style: TextStyle(
                      fontSize: isDesktop ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
    List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) {
      return 'Oroquieta City';
    }

    final place = placemarks[0];
    final addressParts = <String>[];

    if (place.street != null && place.street!.isNotEmpty) {
      addressParts.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      addressParts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      addressParts.add(place.locality!);
    }
    if (place.administrativeArea != null &&
        place.administrativeArea!.isNotEmpty) {
      addressParts.add(place.administrativeArea!);
    }
    if (place.postalCode != null && place.postalCode!.isNotEmpty) {
      addressParts.add(place.postalCode!);
    }
    if (place.country != null && place.country!.isNotEmpty) {
      addressParts.add(place.country!);
    }

    return addressParts.isNotEmpty ? addressParts.join(', ') : 'Oroquieta City';
  } catch (e) {
    return 'Oroquieta City';
  }
}
