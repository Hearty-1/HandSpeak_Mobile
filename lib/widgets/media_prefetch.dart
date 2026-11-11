import 'package:flutter/material.dart';

import '/services/performance_monitor.dart';
import '/widgets/activity_video.dart';

/// Starts loading a round's pictures and videos in the background as soon as
/// its questions are picked, so each question's media is ready when it shows.
class MediaPrefetch {
  static final RegExp _video = RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false);

  static bool _isVideo(String url) => _video.hasMatch(Uri.decodeComponent(url.split('?').first));

  /// Every web link (http / https) found in the questions: question pictures
  /// and videos, options, matching / sequence pieces.
  static Iterable<String> _links(Object? v) sync* {
    if (v is String) {
      for (final part in v.split('|||')) {
        final s = part.trim();
        if (s.startsWith('http://') || s.startsWith('https://')) yield s;
      }
    } else if (v is Iterable) {
      for (final e in v) {
        yield* _links(e);
      }
    } else if (v is Map) {
      for (final e in v.values) {
        yield* _links(e);
      }
    }
  }

  static void questions(BuildContext context, List<Map<String, dynamic>> questions) {
    // Light mode (slow phone): load each question's media only when it shows.
    if (PerformanceSettings.on) return;
    final seen = <String>{};
    for (final q in questions) {
      for (final url in _links(q)) {
        if (!seen.add(url)) continue;
        if (_isVideo(url)) {
          ActivityVideo.prefetch(url);
        } else if (context.mounted) {
          precacheImage(NetworkImage(url), context, onError: (_, _) {});
        }
      }
    }
  }
}
