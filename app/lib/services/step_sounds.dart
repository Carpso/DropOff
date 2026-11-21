// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
// Step-completion sounds (owner request 2026-11-20).
//
// A short, pleasant chime fires whenever a delivery step is completed
// (pickup filed, parcel dropped at the depot, handover confirmed, receipt
// uploaded) and a softer low tone fires on a rejected step. The owner asked
// for this to be an OPTION, so it is a persisted toggle in Account →
// "Step completion sound" (on by default).
//
// Playback is best-effort and never blocks the UI: if the player fails to
// initialise (no audio hardware, web without a user gesture yet, etc.) the
// step still completes silently.

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StepSounds {
  const StepSounds._();

  static const String _prefKey = 'step_sounds_enabled';
  static const String _voicePrefKey = 'voice_guidance_enabled';

  static bool _enabled = true;
  static bool _voiceGuidance = true;
  static bool _loaded = false;
  static final AudioPlayer _player = AudioPlayer();

  /// Whether the chime is currently allowed to play.
  static bool get enabled => _enabled;

  /// Whether spoken turn-by-turn guidance is allowed (separate from chimes).
  static bool get voiceGuidance => _voiceGuidance;

  /// Reads the persisted preferences once per app run.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
      _voiceGuidance = prefs.getBool(_voicePrefKey) ?? true;
    } catch (_) {
      // Fail open: default to on.
    }
    _loaded = true;
  }

  /// Persists the owner's choice (Account toggle).
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {/* preference is a nicety — never break the toggle */}
  }

  /// Persists the voice-guidance choice (Account toggle + navigator button).
  static Future<void> setVoiceGuidance(bool value) async {
    _voiceGuidance = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voicePrefKey, value);
    } catch (_) {/* preference is a nicety — never break the toggle */}
  }

  /// A step was completed successfully.
  static Future<void> stepDone() => _play('sounds/step_done.wav');

  /// A step was rejected / failed (wrong code, upload error, …).
  static Future<void> stepError() => _play('sounds/step_error.wav');

  static Future<void> _play(String asset) async {
    if (!_loaded) await load();
    if (!_enabled) return;
    try {
      // One player, newest cue wins — a rapid double-tap never overlaps two
      // chimes into a clang.
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {
      // Never let audio break a completed delivery step.
    }
  }
}
