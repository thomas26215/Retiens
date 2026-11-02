import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/scheduler.dart';

/// Effets sonores (fichiers `assets/sounds/<nom>.ogg`, générés par
/// `tool/synth_sounds.py`).
enum Sfx {
  tap,
  toggle,
  swipe,
  again,
  hard,
  good,
  easy,
  complete,
  levelup,
  streak,
  postpone,
  undo,
  add,
  delete,
}

/// Sons et vibrations de l'interface.
///
/// Inactif tant que [init] n'a pas été appelé (tests, captures) : aucun son,
/// aucune vibration, aucun minuteur.
class Fx {
  Fx._();

  static final Fx instance = Fx._();

  bool sound = true;
  bool haptics = true;

  bool _ready = false;
  final Map<Sfx, AudioPool> _pools = {};

  // Volume relatif de chaque son (les petits clics restent discrets).
  static const _volume = <Sfx, double>{
    Sfx.tap: 0.35,
    Sfx.toggle: 0.4,
    Sfx.swipe: 0.5,
    Sfx.postpone: 0.7,
    Sfx.undo: 0.7,
    Sfx.add: 0.8,
    Sfx.delete: 0.8,
  };

  /// Prépare les sons en arrière-plan ; ils jouent dès qu'ils sont chargés.
  /// Les sons se mêlent à la musique en cours au lieu de la couper.
  Future<void> init() async {
    _ready = true;
    try {
      final ctx = AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build();
      await AudioPlayer.global.setAudioContext(ctx);
      for (final s in Sfx.values) {
        _pools[s] = await AudioPool.create(
          source: AssetSource('sounds/${s.name}.ogg'),
          maxPlayers: 3,
          playerMode: PlayerMode.lowLatency,
          audioContext: ctx,
        );
      }
    } catch (e) {
      debugPrint('Sons indisponibles : $e');
    }
  }

  /// Joue [s], éventuellement après [delay].
  void play(Sfx s, {Duration delay = Duration.zero}) {
    if (!_ready || !sound) return;
    void start() {
      final pool = _pools[s];
      if (pool == null) return;
      pool.start(volume: _volume[s] ?? 1).ignore();
    }

    delay == Duration.zero ? start() : Timer(delay, start);
  }

  /// Suite de vibrations : (délai depuis le début, intensité).
  void _buzz(List<(int, _Haptic)> pattern) {
    if (!_ready || !haptics) return;
    for (final (ms, kind) in pattern) {
      void go() => switch (kind) {
            _Haptic.select => HapticFeedback.selectionClick(),
            _Haptic.light => HapticFeedback.lightImpact(),
            _Haptic.medium => HapticFeedback.mediumImpact(),
            _Haptic.heavy => HapticFeedback.heavyImpact(),
          };
      ms == 0 ? go() : Timer(Duration(milliseconds: ms), go);
    }
  }

  // --- Événements ----------------------------------------------------------

  /// Navigation (onglets) : vibration seule, sans son.
  void select() => _buzz([(0, _Haptic.select)]);

  void tap() {
    play(Sfx.tap);
    _buzz([(0, _Haptic.select)]);
  }

  void toggle() {
    play(Sfx.toggle);
    _buzz([(0, _Haptic.select)]);
  }

  /// Carte glissée assez loin pour déclencher l'action.
  void swipeArmed() {
    play(Sfx.swipe);
    _buzz([(0, _Haptic.medium)]);
  }

  /// Révision notée : un son et un rythme de vibrations par note.
  void rated(Rating r) {
    switch (r) {
      case Rating.again:
        play(Sfx.again);
        _buzz([(0, _Haptic.medium), (110, _Haptic.light)]);
      case Rating.hard:
        play(Sfx.hard);
        _buzz([(0, _Haptic.medium), (90, _Haptic.select)]);
      case Rating.good:
        play(Sfx.good);
        _buzz([(0, _Haptic.light), (85, _Haptic.medium)]);
      case Rating.easy:
        play(Sfx.easy);
        _buzz([
          (0, _Haptic.light),
          (55, _Haptic.light),
          (110, _Haptic.light),
          (165, _Haptic.heavy),
        ]);
    }
  }

  /// Plus rien à revoir aujourd'hui.
  void dayComplete({Duration delay = Duration.zero}) {
    play(Sfx.complete, delay: delay);
    final d = delay.inMilliseconds;
    _buzz([
      for (var i = 0; i < 5; i++) (d + i * 75, _Haptic.light),
      (d + 420, _Haptic.heavy),
      (d + 560, _Haptic.medium),
    ]);
  }

  /// Un souvenir devient solide (ou ancré).
  void levelUp({Duration delay = Duration.zero}) {
    play(Sfx.levelup, delay: delay);
    final d = delay.inMilliseconds;
    _buzz([(d + 180, _Haptic.medium), (d + 280, _Haptic.heavy)]);
  }

  /// Première révision du jour : la série continue.
  void streak({Duration delay = Duration.zero}) {
    play(Sfx.streak, delay: delay);
    final d = delay.inMilliseconds;
    _buzz([
      (d + 50, _Haptic.light),
      (d + 95, _Haptic.light),
      (d + 140, _Haptic.medium),
    ]);
  }

  void postponed() {
    play(Sfx.postpone);
    _buzz([(0, _Haptic.light), (120, _Haptic.select)]);
  }

  void undone() {
    play(Sfx.undo);
    _buzz([(0, _Haptic.select), (90, _Haptic.light)]);
  }

  void added() {
    play(Sfx.add);
    _buzz([(0, _Haptic.medium)]);
  }

  void deleted() {
    play(Sfx.delete);
    _buzz([(0, _Haptic.heavy)]);
  }

  /// Action impossible (champ manquant) : double vibration, sans son.
  void error() => _buzz([(0, _Haptic.heavy), (110, _Haptic.medium)]);
}

enum _Haptic { select, light, medium, heavy }
