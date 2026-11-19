import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/providers/language_provider.dart';

/// A release published for Android (Firestore `app_config/android_release`,
/// written by tools/publish_release.py):
///
///   versionCode   int     the build number (pubspec "1.0.2+3" -> 3)
///   versionName   string  "1.0.2"
///   apkUrl        string  https download URL or a Firebase Storage path
///   sizeBytes     int     shown before downloading
///   notes         list    "What's new" lines
///   minVersionCode int    older builds must update (no "Later")
class AppRelease {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final int sizeBytes;
  final List<String> notes;
  final int minVersionCode;
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sizeBytes,
    required this.notes,
    required this.minVersionCode,
  });

  static AppRelease? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    // The names tools/publish_release.py writes, plus the ones the web
    // dashboard's "Mobile App" upload may use (downloadUrl, size, ...).
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
    final code = asInt(d['versionCode'] ?? d['buildNumber']) ?? 0;
    final url = (d['apkUrl'] ?? d['downloadUrl'] ?? d['url'] ?? '').toString().trim();
    if (code <= 0 || url.isEmpty) return null;
    final rawNotes = d['notes'] ?? d['releaseNotes'] ?? d['whatsNew'];
    return AppRelease(
      versionCode: code,
      versionName: (d['versionName'] ?? d['version'] ?? '').toString(),
      apkUrl: url,
      sizeBytes: asInt(d['sizeBytes'] ?? d['size']) ?? 0,
      notes: rawNotes is List
          ? [for (final n in rawNotes) if ('$n'.trim().isNotEmpty) '$n'.trim()]
          : [for (final n in '${rawNotes ?? ''}'.split('\n')) if (n.trim().isNotEmpty) n.trim()],
      minVersionCode: asInt(d['minVersionCode']) ?? 0,
    );
  }

  String get sizeText => sizeBytes <= 0 ? '' : '${(sizeBytes / (1024 * 1024)).round()} MB';
}

/// The installed version and the newest release, plus the update dialog.
class AppUpdateService {
  AppUpdateService._();

  static final ValueNotifier<AppRelease?> available = ValueNotifier<AppRelease?>(null);
  static PackageInfo? _info;
  static bool _askedThisSession = false;
  static const String _skipKey = 'update_skipped_version';

  static Future<PackageInfo> info() async => _info ??= await PackageInfo.fromPlatform();

  static Future<int> currentCode() async => int.tryParse((await info()).buildNumber) ?? 0;

  /// "v1.0.1 (2)"
  static Future<String> currentLabel() async {
    final i = await info();
    return 'v${i.version} (${i.buildNumber})';
  }

  /// The newest release when it is newer than this app, else null. Android
  /// only (the release is an APK).
  static Future<AppRelease?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('android_release')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final r = AppRelease.fromMap(doc.data());
      final newer = r != null && r.versionCode > await currentCode() ? r : null;
      available.value = newer;
      return newer;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Once per app start: asks about a newer release, unless the user chose
  /// "Later" for this version already (a required update always asks).
  static Future<void> checkOnLaunch(BuildContext context) async {
    if (_askedThisSession) return;
    _askedThisSession = true;
    final r = await check();
    if (r == null || !context.mounted) return;
    final required = r.minVersionCode > await currentCode();
    if (!required) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getInt(_skipKey) == r.versionCode) return;
      } catch (_) {}
    }
    if (context.mounted) await showUpdateDialog(context, r);
  }

  static Future<bool> _onMobileData() async {
    try {
      final c = await Connectivity().checkConnectivity();
      return c.contains(ConnectivityResult.mobile) && !c.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  /// "Update available" with the size, a mobile-data warning, What's new,
  /// and Later / Download and install.
  static Future<void> showUpdateDialog(BuildContext context, AppRelease r) async {
    final required = r.minVersionCode > await currentCode();
    final mobile = await _onMobileData();
    if (!context.mounted) return;
    final size = r.sizeText;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: !required,
      builder: (c) {
        final theme = Theme.of(c);
        return PopScope(
          canPop: !required,
          child: AlertDialog(
            title: Text(L.t('Update available', 'May bagong update'), style: const TextStyle(fontWeight: FontWeight.w900)),
            content: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(L.t(
                  'Version ${r.versionName} is ready${size.isEmpty ? '' : ' ($size)'}. Your progress and account stay as they are.',
                  'Handa na ang bersyon ${r.versionName}${size.isEmpty ? '' : ' ($size)'}. Mananatili ang iyong progreso at account.',
                )),
                if (required) ...[
                  const SizedBox(height: 10),
                  Text(L.t('This update is required to keep using the app.', 'Kailangan ang update na ito para patuloy na magamit ang app.'),
                      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
                ],
                if (mobile) ...[
                  const SizedBox(height: 10),
                  Text(
                    L.t("You're on mobile data.${size.isEmpty ? '' : ' The download is $size.'}",
                        'Naka-mobile data ka.${size.isEmpty ? '' : ' Ang download ay $size.'}'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(L.t("What's new", 'Mga bago'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final n in r.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $n'),
                    ),
                ],
              ]),
            ),
            actions: [
              if (!required) TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L.t('Later', 'Mamaya'))),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Download and install', 'I-download at i-install')),
              ),
            ],
          ),
        );
      },
    );
    if (go == true) {
      if (context.mounted) await _downloadAndInstall(context, r);
    } else if (!required) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_skipKey, r.versionCode); // not asked again at start for this version
      } catch (_) {}
    }
  }

  static Future<String> _resolve(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final ref = url.startsWith('gs://') ? FirebaseStorage.instance.refFromURL(url) : FirebaseStorage.instance.ref(url);
    return ref.getDownloadURL();
  }

  static Future<void> _downloadAndInstall(BuildContext context, AppRelease r) async {
    final progress = ValueNotifier<double?>(null);
    final status = ValueNotifier<String>(L.t('Downloading...', 'Nagda-download...'));
    var cancelled = false;
    http.Client? client;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(L.t('Updating HandSpeak', 'Ina-update ang HandSpeak')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, p, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(value: p, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                Text(p == null ? '' : '${(p * 100).round()}%'),
              ]),
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<String>(valueListenable: status, builder: (_, s, _) => Text(s)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                client?.close();
                Navigator.pop(c);
              },
              child: Text(L.t('Cancel', 'Kanselahin')),
            ),
          ],
        ),
      ),
    );

    void closeDialog() {
      if (!cancelled && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/handspeak-${r.versionName.isEmpty ? r.versionCode : r.versionName}.apk');
      final done = r.sizeBytes > 0 && await file.exists() && await file.length() == r.sizeBytes;
      if (!done) {
        client = http.Client();
        final res = await client.send(http.Request('GET', Uri.parse(await _resolve(r.apkUrl))));
        if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        final total = res.contentLength ?? r.sizeBytes;
        final part = File('${file.path}.part');
        final sink = part.openWrite();
        var got = 0;
        try {
          await for (final chunk in res.stream) {
            if (cancelled) break;
            sink.add(chunk);
            got += chunk.length;
            if (total > 0) progress.value = got / total;
          }
        } finally {
          await sink.close();
          client.close();
        }
        if (cancelled) {
          if (await part.exists()) await part.delete();
          return;
        }
        if (await file.exists()) await file.delete();
        await part.rename(file.path);
      }
      progress.value = 1;
      status.value = L.t('Opening the installer...', 'Binubuksan ang installer...');
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      closeDialog();
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(L.t(
            'Could not open the installer. Allow HandSpeak to install apps (Settings > Apps > Special access > Install unknown apps), then try again.',
            'Hindi mabuksan ang installer. Payagan ang HandSpeak na mag-install ng apps (Settings > Apps > Special access > Install unknown apps), saka subukang muli.',
          )),
        ));
      }
    } catch (e) {
      debugPrint('Update download failed: $e');
      closeDialog();
      if (!cancelled && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(L.t('The download failed. Check your internet connection and try again.',
              'Nabigo ang download. Tingnan ang koneksyon sa internet at subukang muli.')),
        ));
      }
    }
  }
}
