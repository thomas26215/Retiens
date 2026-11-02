import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../data/app_state.dart';
import '../data/sync_merge.dart';

enum SyncStatus {
  /// Pas de configuration Firebase dans cette version de l'app.
  unavailable,
  signedOut,
  syncing,
  synced,

  /// Pas de réseau : les changements partiront au retour de la connexion.
  offline,
  error,
}

/// Compte (e-mail + mot de passe) et synchronisation automatique des données
/// avec Firestore (document `users/{uid}`).
///
/// - À la connexion, les données de l'appareil et celles du compte sont
///   fusionnées (rien n'est perdu d'un côté ni de l'autre).
/// - Chaque modification locale est envoyée peu après (regroupées).
/// - Les modifications faites sur un autre appareil arrivent en direct.
/// - Hors connexion, Firestore garde les envois en attente.
class CloudSync extends ChangeNotifier {
  CloudSync._();

  static final CloudSync instance = CloudSync._();

  SyncStatus status = SyncStatus.unavailable;
  User? user;
  DateTime? lastSync;
  String? lastError;

  bool get available => status != SyncStatus.unavailable;
  bool get signedIn => user != null;

  AppState? _app;
  FirebaseAuth? _auth;
  FirebaseFirestore? _db;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  Timer? _debounce;
  bool _forceNext = false;
  String? _lastPushed;

  /// Vrai dès que le serveur a répondu une fois pour ce compte. Avant, l'état
  /// du compte est inconnu (le cache peut être vide) : on n'envoie rien, pour
  /// ne jamais écraser le compte avec les données d'un nouvel appareil.
  bool _seenServer = false;

  /// Démarre Firebase. Sans configuration, la synchronisation reste
  /// indisponible et l'app fonctionne en local.
  Future<void> init(AppState app) async {
    _app = app;
    try {
      await Firebase.initializeApp();
      _auth = FirebaseAuth.instance;
      _db = FirebaseFirestore.instance;
    } catch (e) {
      debugPrint('Synchronisation indisponible : $e');
      _set(SyncStatus.unavailable);
      return;
    }
    app.onLocalChange = _onLocalChange;
    _set(SyncStatus.signedOut);
    _authSub = _auth!.authStateChanges().listen(_onUser);
  }

  void _set(SyncStatus s, {String? error}) {
    status = s;
    lastError = error;
    if (s == SyncStatus.synced) lastSync = DateTime.now();
    notifyListeners();
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db!.collection('users').doc(uid);

  // --- Compte ----------------------------------------------------------------

  /// Crée un compte. Renvoie un message d'erreur, ou `null` si tout va bien.
  Future<String?> signUp(String email, String password) => _guard(() =>
      _auth!.createUserWithEmailAndPassword(email: email, password: password));

  Future<String?> signIn(String email, String password) => _guard(() =>
      _auth!.signInWithEmailAndPassword(email: email, password: password));

  Future<String?> resetPassword(String email) =>
      _guard(() => _auth!.sendPasswordResetEmail(email: email));

  /// Déconnexion : les données restent sur l'appareil, sans synchronisation.
  Future<void> signOut() async {
    await _flush();
    await _auth?.signOut();
  }

  /// Supprime les données du compte puis le compte, après avoir revérifié le
  /// mot de passe (exigé par Firebase, et évite d'effacer les données sans
  /// pouvoir supprimer le compte). Les données restent sur cet appareil.
  Future<String?> deleteAccount(String password) async {
    final u = user;
    final email = u?.email;
    if (u == null || email == null) return null;
    return _guard(() async {
      await u.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      _debounce?.cancel();
      await _docSub?.cancel();
      _docSub = null;
      await _doc(u.uid).delete();
      await u.delete();
    });
  }

  Future<String?> _guard(Future<void> Function() action) async {
    if (_auth == null) return 'La synchronisation n\'est pas disponible.';
    try {
      await action();
      return null;
    } on FirebaseAuthException catch (e) {
      return authMessage(e.code, e.message);
    } on FirebaseException catch (e) {
      return e.code == 'unavailable'
          ? 'Pas de connexion internet.'
          : 'Erreur du serveur (${e.code}).';
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }

  /// Message en français pour une erreur de connexion Firebase.
  static String authMessage(String code, [String? detail]) {
    // Authentication pas encore activé dans la console (projet neuf).
    if (detail != null && detail.contains('CONFIGURATION_NOT_FOUND')) {
      return 'La connexion par e-mail n\'est pas activée dans la console '
          'Firebase (Authentication → Sign-in method).';
    }
    return switch (code) {
        'email-already-in-use' => 'Un compte existe déjà avec cet e-mail.',
        'invalid-email' => 'Cette adresse e-mail n\'est pas valide.',
        'weak-password' => 'Mot de passe trop faible (6 caractères minimum).',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'E-mail ou mot de passe incorrect.',
        'user-disabled' => 'Ce compte a été désactivé.',
        'too-many-requests' =>
          'Trop de tentatives. Réessaie dans quelques minutes.',
        'network-request-failed' => 'Pas de connexion internet.',
        'requires-recent-login' =>
          'Par sécurité, déconnecte-toi puis reconnecte-toi avant de supprimer le compte.',
        'operation-not-allowed' =>
          'La connexion par e-mail n\'est pas activée dans la console Firebase.',
        _ => 'Erreur de connexion ($code).',
      };
  }

  // --- Synchronisation -------------------------------------------------------

  Future<void> _onUser(User? u) async {
    await _docSub?.cancel();
    _docSub = null;
    _debounce?.cancel();
    _lastPushed = null;
    _seenServer = false;
    user = u;
    if (u == null) {
      _set(SyncStatus.signedOut);
      return;
    }
    _set(SyncStatus.syncing);
    _docSub = _doc(u.uid)
        .snapshots(includeMetadataChanges: true)
        .listen(_onSnapshot, onError: _onError);
  }

  /// Nouvel état du compte (premier chargement, autre appareil, ou accusé de
  /// réception de nos propres envois).
  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final app = _app;
    if (app == null) return;
    // Écho local d'un envoi pas encore confirmé par le serveur.
    if (snap.metadata.hasPendingWrites) return;

    final fromCache = snap.metadata.isFromCache;
    if (!fromCache) _seenServer = true;
    final remote = _normalize(snap.data());
    // Compte encore inconnu (cache vide ou pas encore de réponse du serveur) :
    // on attend le serveur.
    if (!_seenServer && remote == null) return;
    final local = app.toCloud();
    final merged = remote == null
        ? local
        : mergeCloud(
            local,
            remote,
            deviceId: app.deviceId,
            now: DateTime.now().millisecondsSinceEpoch,
          );
    final mergedKey = canonical(merged);
    if (mergedKey != canonical(local)) app.applyCloud(merged);
    if (!_seenServer) {
      // Données du cache affichées, envoi après la réponse du serveur.
      _set(SyncStatus.syncing);
      return;
    }
    if (remote == null || mergedKey != canonical(remote)) {
      _write(merged);
    } else {
      _lastPushed = mergedKey;
    }
    if (!_pending) {
      _set(fromCache ? SyncStatus.offline : SyncStatus.synced);
    }
  }

  void _onError(Object e) {
    debugPrint('Synchronisation : $e');
    final denied = e is FirebaseException && e.code == 'permission-denied';
    _set(
      SyncStatus.error,
      error: denied
          ? 'Accès refusé : vérifie les règles Firestore.'
          : 'La synchronisation a échoué.',
    );
  }

  bool get _pending => _debounce?.isActive ?? false;

  void _onLocalChange({required bool authoritative}) {
    if (user == null) return;
    if (authoritative) _forceNext = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), _push);
  }

  void _push() {
    final app = _app;
    // Avant la première réponse du serveur, la fusion qui suivra l'inclura.
    if (app == null || user == null || !_seenServer) return;
    final data = app.toCloud();
    if (!_forceNext && canonical(data) == _lastPushed) return;
    _forceNext = false;
    _write(data);
  }

  /// Envoie tout de suite ce qui est en attente (avant déconnexion).
  Future<void> _flush() async {
    if (_pending) {
      _debounce!.cancel();
      _push();
    }
  }

  /// Relit le compte depuis le serveur et renvoie l'état fusionné.
  Future<void> syncNow() async {
    final u = user;
    if (u == null) return;
    _set(SyncStatus.syncing);
    try {
      final snap = await _doc(u.uid).get(const GetOptions(source: Source.server));
      _onSnapshot(snap);
      if (status == SyncStatus.syncing) _set(SyncStatus.synced);
    } on FirebaseException catch (e) {
      _set(
        e.code == 'unavailable' ? SyncStatus.offline : SyncStatus.error,
        error: e.code == 'unavailable' ? null : 'La synchronisation a échoué.',
      );
    }
  }

  void _write(CloudState data) {
    final u = user;
    if (u == null) return;
    _lastPushed = canonical(data);
    _set(SyncStatus.syncing);
    _doc(u.uid)
        .set({
          ...data,
          'schema': 1,
          'syncedAt': FieldValue.serverTimestamp(),
        })
        .then(
          (_) {
            if (!_pending && status == SyncStatus.syncing) {
              _set(SyncStatus.synced);
            }
          },
          onError: _onError,
        );
  }

  /// Données du compte au format JSON pur (sans horodatage serveur), pour
  /// pouvoir les comparer et les fusionner.
  static CloudState? _normalize(Map<String, dynamic>? data) {
    if (data == null) return null;
    final copy = Map<String, dynamic>.of(data)
      ..remove('syncedAt')
      ..remove('schema');
    return jsonDecode(jsonEncode(copy)) as CloudState;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _docSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
