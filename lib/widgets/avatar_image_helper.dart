import 'dart:convert';
import 'package:flutter/material.dart';

/// Helper to get an [ImageProvider] from an avatar URL or Base64 string.
/// Supports both HTTP/HTTPS network URLs and Base64 data URIs (e.g. data:image/jpeg;base64,...).
ImageProvider? getAvatarImageProvider(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return null;
  }

  final trimmed = avatarUrl.trim();

  // Check if it's a data URI or base64 string
  if (trimmed.startsWith('data:image') || trimmed.contains(';base64,')) {
    try {
      final base64Str = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
      final bytes = base64Decode(base64Str);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // Pure Base64 without data URI scheme (length > 100 and no slashes/protocol)
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    try {
      final bytes = base64Decode(trimmed);
      return MemoryImage(bytes);
    } catch (_) {
      // Fallback
    }
  }

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return NetworkImage(trimmed);
  }

  return null;
}

/// Reusable CircleAvatar widget with safe image loading and letter fallback
Widget buildSafeAvatar({
  required String? avatarUrl,
  required String displayName,
  double radius = 22,
  Color? backgroundColor,
  Color? textColor,
  double? fontSize,
}) {
  final imageProvider = getAvatarImageProvider(avatarUrl);
  final initial = displayName.trim().isNotEmpty
      ? displayName.trim()[0].toUpperCase()
      : '👤';

  final bg = backgroundColor ?? const Color(0xFF5B50E6).withValues(alpha: 0.15);
  final fg = textColor ?? const Color(0xFF5B50E6);

  return CircleAvatar(
    radius: radius,
    backgroundColor: bg,
    backgroundImage: imageProvider,
    child: imageProvider == null
        ? Text(
            initial,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: fontSize ?? (radius * 0.8),
            ),
          )
        : null,
  );
}
