import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '/module/civic/civic_tutorial_detail.dart' show CustomVideoPlayer;

/// The demo of a sign in a practice screen: the video (or picture) uploaded
/// from the web app for that lesson (tutorial_lessons, videoUrl / imageUrl),
/// else the bundled [fallbackAsset].
class LessonDemoMedia extends StatefulWidget {
  final String category; // tutorial_lessons.category, e.g. "alphabet"
  final String gestureKey; // "A", "7", ...
  final String fallbackAsset;
  const LessonDemoMedia({super.key, required this.category, required this.gestureKey, required this.fallbackAsset});

  /// mp4 / mov / webm / m4v / 3gp / mkv, also inside a Firebase Storage link
  /// (".../o/folder%2Fclip.mp4?alt=media&token=...").
  static bool isVideo(String url) {
    if (url.isEmpty) return false;
    final path = Uri.decodeComponent(url.split('?').first).toLowerCase();
    return RegExp(r'\.(mp4|mov|webm|m4v|3gp|mkv)$').hasMatch(path);
  }

  /// "category/KEY" -> download URL ('' = none). Read once per app session.
  static final Map<String, Future<String>> _cache = {};

  static Future<String> mediaFor(String category, String gestureKey) {
    final id = '$category/${gestureKey.trim().toUpperCase()}';
    return _cache[id] ??= _fetch(category, gestureKey).catchError((Object _) {
      _cache.remove(id); // offline: try again next time
      return '';
    });
  }

  static Future<String> _fetch(String category, String gestureKey) async {
    final key = gestureKey.trim().toUpperCase();
    final snap = await FirebaseFirestore.instance.collection('tutorial_lessons').where('category', isEqualTo: category).get();
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['isActive'] == false) continue;
      final k = (d['gestureKey'] ?? d['symbol'] ?? '').toString().trim().toUpperCase();
      if (k != key) continue;
      final video = (d['videoUrl'] ?? d['video_url'] ?? '').toString().trim();
      final image = (d['imageUrl'] ?? d['image_url'] ?? d['imageStoragePath'] ?? d['imagePath'] ?? '').toString().trim();
      final url = video.isNotEmpty ? video : image;
      if (url.isEmpty || url.startsWith('assets/') || url.startsWith('data:')) return '';
      if (url.startsWith('http://') || url.startsWith('https://')) return url;
      final ref = url.startsWith('gs://') ? FirebaseStorage.instance.refFromURL(url) : FirebaseStorage.instance.ref(url);
      return ref.getDownloadURL();
    }
    return '';
  }

  @override
  State<LessonDemoMedia> createState() => _LessonDemoMediaState();
}

class _LessonDemoMediaState extends State<LessonDemoMedia> {
  late Future<String> _media = LessonDemoMedia.mediaFor(widget.category, widget.gestureKey);

  @override
  void didUpdateWidget(LessonDemoMedia old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category || old.gestureKey != widget.gestureKey) {
      _media = LessonDemoMedia.mediaFor(widget.category, widget.gestureKey);
    }
  }

  Widget _asset(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      widget.fallbackAsset,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _media,
      builder: (context, snap) {
        // The bundled picture shows until (and unless) an upload is found.
        final url = snap.data ?? '';
        if (url.isEmpty) return _asset(context);
        if (LessonDemoMedia.isVideo(url)) {
          return ColoredBox(color: Colors.black, child: Center(child: CustomVideoPlayer(key: ValueKey(url), videoUrl: url)));
        }
        return Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => _asset(c));
      },
    );
  }
}
