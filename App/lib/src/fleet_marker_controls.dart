import 'package:flutter/material.dart';

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
      Text('Markers', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        active
            ? 'Save your current location. Works offline and without ESP32.'
            : 'Start a Fleet trip to save markers using phone GPS.',
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Take a photo'),
        subtitle: const Text('Optional · compressed before upload'),
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
