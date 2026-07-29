import 'dart:convert';

import 'package:flutter/services.dart';

class VietnamProvinceClassifier {
  List<_ProvincePolygon>? _polygons;

  Future<String?> provinceAt(double lat, double lng) async {
    final polygons = await _load();
    for (final polygon in polygons) {
      if (polygon.contains(lat, lng)) return polygon.name;
    }
    return null;
  }

  Future<List<_ProvincePolygon>> _load() async {
    if (_polygons != null) return _polygons!;
    final raw = await rootBundle.loadString('assets/vietnam-provinces.geojson');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final result = <_ProvincePolygon>[];
    for (final feature
        in (data['features'] as List).cast<Map<String, dynamic>>()) {
      final properties =
          feature['properties'] as Map<String, dynamic>? ?? const {};
      final name =
          (properties['ten_tinh'] ??
                  properties['Name'] ??
                  properties['name'] ??
                  '')
              .toString();
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      if (geometry['type'] == 'Polygon') {
        _addPolygon(result, name, coordinates);
      } else if (geometry['type'] == 'MultiPolygon') {
        for (final polygon in coordinates) {
          _addPolygon(result, name, polygon as List);
        }
      }
    }
    _polygons = result;
    return result;
  }

  void _addPolygon(List<_ProvincePolygon> output, String name, List rings) {
    if (rings.isEmpty) return;
    final outer = (rings.first as List)
        .map((point) => _Coordinate((point as List)[1] as num, point[0] as num))
        .toList();
    if (outer.length >= 3) output.add(_ProvincePolygon(name, outer));
  }
}

class _Coordinate {
  _Coordinate(num lat, num lng) : lat = lat.toDouble(), lng = lng.toDouble();

  final double lat;
  final double lng;
}

class _ProvincePolygon {
  const _ProvincePolygon(this.name, this.points);

  final String name;
  final List<_Coordinate> points;

  bool contains(double lat, double lng) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i];
      final b = points[j];
      final intersects =
          ((a.lat > lat) != (b.lat > lat)) &&
          (lng < (b.lng - a.lng) * (lat - a.lat) / (b.lat - a.lat) + a.lng);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}
