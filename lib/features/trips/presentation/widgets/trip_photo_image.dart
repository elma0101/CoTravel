import 'package:flutter/material.dart';

import '../../domain/trip.dart';

/// Where to draw a host photo from: its bytes before upload, its URL after.
ImageProvider<Object> tripPhotoProvider(TripPhoto photo) {
  final bytes = photo.bytes;
  return bytes != null ? MemoryImage(bytes) : NetworkImage(photo.url);
}
