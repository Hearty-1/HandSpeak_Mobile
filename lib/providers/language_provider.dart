import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language: English (default) or Filipino.
///
/// Saved on the phone (works offline, on the login screen and for guests)
/// and, for signed-in accounts, in `users/{uid}.preferences.language`, so it
/// follows the account to any phone: after login the account's choice wins.
///
/// In widgets use `context.tr('English text', 'Filipino text')`: the widget
/// rebuilds when the language changes. In code outside build (feedback
/// messages set in state, services) use `L.t('English', 'Filipino')`, which
/// reads the current language.
class LanguageProvider extends ChangeNotifier {
  static const String _prefKey = 'app_language';
  static const String english = 'en';
  static const String filipino = 'fil';

  /// Current language for code without a BuildContext (see [L]).
  static String current = english;

  String _code = english;
  String get code => _code;
  bool get isFilipino => _code == filipino;

  StreamSubscription<User?>? _authSub;
  String? _loadedForUid;

  LanguageProvider() {
    _loadLocal();
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    } catch (_) {}
  }

  static bool _valid(Object? c) => c == english || c == filipino;

  /// Account users only: guests (anonymous) keep the phone setting.
  static User? get _account {
    final u = FirebaseAuth.instance.currentUser;
    return (u == null || u.isAnonymous) ? null : u;
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (_valid(saved)) _apply(saved!);
    } catch (_) {}
  }

  /// After login: the account's saved language, if it has one; otherwise the
  /// phone's current choice is saved to the account.
  Future<void> _onAuth(User? user) async {
    if (user == null || user.isAnonymous) {
      _loadedForUid = null;
      return;
    }
    if (_loadedForUid == user.uid) return;
    _loadedForUid = user.uid;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final prefs = doc.data()?['preferences'];
      final saved = prefs is Map ? prefs['language'] : null;
      if (_valid(saved)) {
        _apply(saved as String);
        await _saveLocal(saved);
      } else {
        await _saveToAccount(_code);
      }
    } catch (e) {
      debugPrint('Language preference not loaded from the account: $e');
    }
  }

  void _apply(String code) {
    if (code == _code) return;
    _code = code;
    current = code;
    notifyListeners();
    _rebuildAllScreens();
  }

  Future<void> _saveLocal(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }

  Future<void> _saveToAccount(String code) async {
    final user = _account;
    if (user == null) return;
    try {
      // Queued by Firestore when offline, sent when back online.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'preferences': {'language': code},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Language preference not saved to the account: $e');
    }
  }

  Future<void> setLanguage(String code) async {
    if (!_valid(code) || code == _code) return;
    _apply(code);
    await _saveLocal(code);
    await _saveToAccount(code);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Redraws every open screen once (text written with [L.t] has no listener),
/// so a language change shows everywhere at once, including the screens
/// still open under Settings.
void _rebuildAllScreens() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Text for the current language, outside widgets.
class L {
  static bool get isFilipino => LanguageProvider.current == LanguageProvider.filipino;
  static String t(String en, String fil) => isFilipino ? fil : en;

  static const Map<String, String> _fingerEn = {
    'hinlalaki': 'thumb',
    'hintuturo': 'index finger',
    'hinlalato': 'middle finger',
    'palasingsingan': 'ring finger',
    'kalingkingan': 'pinky',
    'hinliliit': 'pinky',
  };

  /// Finger names are kept in Filipino in the recognizers; this shows them
  /// in the current language ("hintuturo, hinlalato" / "index finger, middle finger").
  static String fingers(Iterable<String> filipinoNames) =>
      filipinoNames.map((f) => isFilipino ? f : (_fingerEn[f] ?? f)).join(', ');
}

extension LanguageContext on BuildContext {
  /// Text for the current language; the widget rebuilds when it changes.
  String tr(String en, String fil) => watch<LanguageProvider>().isFilipino ? fil : en;
}
