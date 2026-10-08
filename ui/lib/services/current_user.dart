import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Which account is signed in on this phone, for keeping each account's
/// data apart: its document library, PIN, cloud connections and backup
/// settings. Set by the AuthGate on sign-in / app start, cleared on sign-out.
///
/// The key is derived from the email (hashed, so it can be used in folder
/// names and storage keys without exposing the address).
class CurrentUser {
  CurrentUser._();

  static String? _key;
  static final List<void Function()> _listeners = [];

  /// Short stable id of the signed-in account, or null when nobody is.
  static String? get key => _key;

  static String? keyForEmail(String? email) {
    final normalized = email?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return null;
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 16);
  }

  /// Switches to [email]'s account (null = signed out) and tells the
  /// per-account stores to drop whatever they cached for the previous one.
  static void setEmail(String? email) {
    final key = keyForEmail(email);
    if (key == _key) return;
    _key = key;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  static void addListener(void Function() listener) => _listeners.add(listener);

  /// [base] made specific to the current account (e.g. a preferences key).
  /// Unchanged when nobody is signed in.
  static String scoped(String base) => _key == null ? base : '$base.u.$_key';
}
