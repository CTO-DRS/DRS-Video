import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Drives the in-app floating video window (v1.3.0).
///
/// YouTube/TikTok-style: when the full player screen is closed while a
/// video keeps playing, the video shrinks into a small draggable window
/// that floats above the app content. The window can be dragged, tapped
/// to re-open the player, or closed (which stops playback).
///
/// Kept deliberately framework-free for testability: [attach] receives a
/// listenable (PlayerService) plus a `hasMedia` probe; when playback
/// stops, the window hides itself.
class FloatingPlayerController extends ChangeNotifier {
  bool _visible = false;

  /// Window top-left position in logical pixels (clamped by the widget).
  Offset _offset = Offset.zero;

  /// Marks that the widget already applied the default anchor once, so a
  /// later [show] keeps the user's last position.
  bool _anchorInitialized = false;

  Listenable? _source;
  VoidCallback? _sourceListener;
  bool Function()? _hasMedia;

  bool get visible => _visible;
  Offset get offset => _offset;
  bool get anchorInitialized => _anchorInitialized;

  /// Wires the auto-hide behavior: whenever [hasMedia] turns false while
  /// the window is visible, the window hides. Never throws.
  void attach(Listenable player, bool Function() hasMedia) {
    if (_source != null && _sourceListener != null) {
      _source!.removeListener(_sourceListener!);
    }
    _source = player;
    _hasMedia = hasMedia;
    _sourceListener = () {
      if (_visible && !(_hasMedia?.call() ?? false)) {
        _visible = false;
      }
      notifyListeners();
    };
    player.addListener(_sourceListener!);
  }

  /// Shows the floating window (playback continues under it).
  void show() {
    _visible = true;
    notifyListeners();
  }

  /// Hides the window without touching playback.
  void hide() {
    _visible = false;
    notifyListeners();
  }

  /// True when the window just transitioned from hidden to visible —
  /// used by the widget to apply the default anchor position once.
  void setOffset(Offset o) {
    _offset = o;
    _anchorInitialized = true;
    notifyListeners();
  }

  /// Moves the window while dragging (no notify spam per pixel — the
  /// widget rebuilds itself via setState during drag).
  void dragTo(Offset o) {
    _offset = o;
    _anchorInitialized = true;
  }

  @override
  void dispose() {
    if (_source != null && _sourceListener != null) {
      _source!.removeListener(_sourceListener!);
    }
    super.dispose();
  }
}
