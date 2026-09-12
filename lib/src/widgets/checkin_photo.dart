import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/checkin.dart';
import '../repositories/local_image_storage.dart';
import '../theme/app_colors.dart';

class CheckInPhoto extends StatelessWidget {
  const CheckInPhoto({
    super.key,
    required this.item,
    required this.remoteUrl,
    this.fit = BoxFit.cover,
    this.emptyIconSize = 20,
    this.errorText,
  });

  final CheckIn item;
  final String Function(String path) remoteUrl;
  final BoxFit fit;
  final double emptyIconSize;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final asset = item.primaryPhoto;
    if (asset?.localPhoto.isNotEmpty == true) {
      return FutureBuilder<Uint8List?>(
        future: LocalImageStorage.readImage(asset!.localPhoto),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(bytes, fit: fit);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _RemoteOrFallback(
            item: item,
            remoteUrl: remoteUrl,
            fit: fit,
            emptyIconSize: emptyIconSize,
            errorText: errorText,
          );
        },
      );
    }
    return _RemoteOrFallback(
      item: item,
      remoteUrl: remoteUrl,
      fit: fit,
      emptyIconSize: emptyIconSize,
      errorText: errorText,
    );
  }
}

class _RemoteOrFallback extends StatelessWidget {
  const _RemoteOrFallback({
    required this.item,
    required this.remoteUrl,
    required this.fit,
    required this.emptyIconSize,
    required this.errorText,
  });

  final CheckIn item;
  final String Function(String path) remoteUrl;
  final BoxFit fit;
  final double emptyIconSize;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final asset = item.primaryPhoto;
    if (asset == null || asset.photo.isEmpty) {
      return Icon(
        Icons.image_outlined,
        size: emptyIconSize,
        color: colors.muted,
      );
    }
    return Image.network(
      remoteUrl(asset.photo),
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (errorText != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ),
          );
        }
        return Icon(
          Icons.broken_image_outlined,
          size: emptyIconSize,
          color: colors.muted,
        );
      },
    );
  }
}
