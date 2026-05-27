import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A map viewer widget that displays a location on a map
/// Uses OpenStreetMap tiles (no API key required)
/// Centered on Oroquieta City, Philippines by default
class OroquietaMapViewer extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? address;

  const OroquietaMapViewer({
    super.key,
    this.latitude,
    this.longitude,
    this.locationName,
    this.address,
  });

  @override
  State<OroquietaMapViewer> createState() => _OroquietaMapViewerState();
}

class _OroquietaMapViewerState extends State<OroquietaMapViewer> {
  // Oroquieta City coordinates (default center)
  static const double _oroquietaLat = 8.4885;
  static const double _oroquietaLng = 123.8047;

  final MapController _mapController = MapController();

  double get _initialZoom {
    return (widget.latitude != null && widget.longitude != null) ? 15.0 : 13.0;
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    final newZoom = (currentZoom + 1).clamp(10.0, 19.0);
    _mapController.move(_mapController.camera.center, newZoom);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    final newZoom = (currentZoom - 1).clamp(10.0, 19.0);
    _mapController.move(_mapController.camera.center, newZoom);
  }

  @override
  Widget build(BuildContext context) {
    // Use provided coordinates or default to Oroquieta City
    final lat = widget.latitude ?? _oroquietaLat;
    final lng = widget.longitude ?? _oroquietaLng;
    final center = LatLng(lat, lng);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.locationName ??
              widget.address ??
              'Oroquieta City, Philippines',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _initialZoom,
              minZoom: 10.0,
              maxZoom:
                  19.0, // Increased to show more detail (houses, buildings)
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // Enables pinch-to-zoom, pan, etc.
              ),
            ),
            children: [
              // OpenStreetMap tile layer (no API key needed)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lawconnect.app',
                maxZoom: 19, // High zoom level to show detailed features
              ),
              // Marker layer
              if (widget.latitude != null && widget.longitude != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFF1A4D8F), // Royal Blue
                        size: 50,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Zoom controls (+ and - buttons)
          Positioned(
            top: 80,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Zoom In button (+)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomIn,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.black87,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  // Divider line
                  Container(width: 48, height: 1, color: Colors.grey[300]),
                  // Zoom Out button (-)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomOut,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: const Icon(
                          Icons.remove,
                          color: Colors.black87,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom info bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.address != null)
                          Text(
                            widget.address!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (widget.address == null &&
                            widget.locationName == null)
                          const Text(
                            'Oroquieta City, Philippines',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Close'),
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
