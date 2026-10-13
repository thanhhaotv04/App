import 'package:flutter/material.dart';

/// Tap-to-read help: the small glyph keeps a full-size touch target.
class FeatureHelp extends StatelessWidget {
  const FeatureHelp({required this.title, required this.message, super.key});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Help about $title',
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: () {
      Tooltip.dismissAllToolTips();
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        requestFocus: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        showDragHandle: true,
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
            maxWidth: 640,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close help',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        ),
      );
    },
    icon: Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      child: ExcludeSemantics(
        child: Text(
          '!',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 13,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

class FeatureHeading extends StatelessWidget {
  const FeatureHeading({required this.title, required this.help, super.key});

  final String title;
  final String help;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      FeatureHelp(title: title, message: help),
    ],
  );
}
