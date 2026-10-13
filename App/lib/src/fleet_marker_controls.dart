import 'package:flutter/material.dart';
import 'feature_help.dart';

class FleetMarkerControls extends StatelessWidget {
  const FleetMarkerControls({
    required this.active,
    required this.busy,
    required this.photo,
    required this.onPhotoChanged,
    required this.onSave,
    super.key,
  });
  final bool active;
  final bool busy;
  final bool photo;
  final ValueChanged<bool> onPhotoChanged;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(height: 32),
      const FeatureHeading(
        title: 'Markers',
        help:
            'During a Fleet ride, save your current phone GPS location as Save Point, '
            'Food or Danger. Markers appear on your fleet dashboard. '
            'Works offline and without ESP32; unsent markers sync when internet returns. '
            'From ESP32, use Menu → Marker while connected to the phone. '
            'Take a photo opens the camera when saving a marker; photos are compressed before upload.',
      ),
      if (!active) const Text('Start a Fleet trip to save markers.'),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Take a photo'),
        value: photo,
        onChanged: active && !busy ? onPhotoChanged : null,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const [
            ('save_point', 'Save Point', Icons.location_on_outlined),
            ('food', 'Food', Icons.restaurant),
            ('danger', 'Danger', Icons.warning_amber_rounded),
          ])
            OutlinedButton.icon(
              key: ValueKey('marker-${entry.$1}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: active && !busy ? () => onSave(entry.$1) : null,
              icon: Icon(entry.$3),
              label: Text(entry.$2),
            ),
        ],
      ),
    ],
  );
}
