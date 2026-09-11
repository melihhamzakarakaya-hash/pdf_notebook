import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';

import '../services/storage_service.dart';

/// Owns one open PDF's handwritten annotations: a lazily-created
/// [ScribbleNotifier] per page, loaded from disk on open and debounce-saved
/// back to disk on every change (plus a forced flush on lifecycle pause and
/// when the screen is left), so annotations always survive an app restart.
class DocumentAnnotationController extends ChangeNotifier with WidgetsBindingObserver {
  DocumentAnnotationController({
    required this.documentId,
    required StorageService storage,
  }) : _storage = storage {
    WidgetsBinding.instance.addObserver(this);
  }

  final String documentId;
  final StorageService _storage;

  final Map<int, ScribbleNotifier> _pageNotifiers = {};
  Map<String, dynamic> _savedStrokesByPage = {};
  bool _loaded = false;

  Timer? _saveDebounce;
  bool _dirty = false;

  Color _selectedColor = Colors.black;
  double _selectedWidth = 3;
  bool _stylusOnly = true;
  DateTime? _lastSavedAt;

  bool get loaded => _loaded;
  Color get selectedColor => _selectedColor;
  double get selectedWidth => _selectedWidth;
  bool get stylusOnly => _stylusOnly;
  DateTime? get lastSavedAt => _lastSavedAt;

  Future<void> load() async {
    _savedStrokesByPage = await _storage.readStrokes(documentId) ?? {};
    _loaded = true;
    notifyListeners();
  }

  /// Returns the notifier for [pageIndex] (0-based), creating and seeding it
  /// from saved strokes on first access.
  ScribbleNotifier notifierForPage(int pageIndex) {
    return _pageNotifiers.putIfAbsent(pageIndex, () {
      Sketch? initialSketch;
      final raw = _savedStrokesByPage[pageIndex.toString()];
      if (raw != null) {
        try {
          initialSketch = Sketch.fromJson(raw as Map<String, dynamic>);
        } catch (_) {
          initialSketch = null;
        }
      }
      final notifier = ScribbleNotifier(
        sketch: initialSketch,
        allowedPointersMode: _stylusOnly ? ScribblePointerMode.penOnly : ScribblePointerMode.all,
      );
      notifier.setColor(_selectedColor);
      notifier.setStrokeWidth(_selectedWidth);
      notifier.addListener(_onPageChanged);
      return notifier;
    });
  }

  void _onPageChanged() {
    _dirty = true;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(flushNow());
    });
  }

  /// Forces an immediate write of every currently-loaded page's strokes.
  /// Call this before navigating away from the viewer, in addition to the
  /// automatic debounce and lifecycle-triggered flushes.
  Future<void> flushNow() async {
    _saveDebounce?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final data = <String, dynamic>{};
    _pageNotifiers.forEach((pageIndex, notifier) {
      data[pageIndex.toString()] = notifier.currentSketch.toJson();
    });
    await _storage.writeStrokes(documentId, data);
    _lastSavedAt = DateTime.now();
    notifyListeners();
  }

  void setColor(Color color) {
    _selectedColor = color;
    for (final notifier in _pageNotifiers.values) {
      notifier.setColor(color);
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _selectedWidth = width;
    for (final notifier in _pageNotifiers.values) {
      notifier.setStrokeWidth(width);
    }
    notifyListeners();
  }

  void setEraserActive(int pageIndex, bool active) {
    final notifier = notifierForPage(pageIndex);
    if (active) {
      notifier.setEraser();
    } else {
      notifier.setColor(_selectedColor);
    }
  }

  void setStylusOnly(bool value) {
    _stylusOnly = value;
    final mode = value ? ScribblePointerMode.penOnly : ScribblePointerMode.all;
    for (final notifier in _pageNotifiers.values) {
      notifier.setAllowedPointersMode(mode);
    }
    notifyListeners();
  }

  void undo(int pageIndex) {
    final notifier = _pageNotifiers[pageIndex];
    if (notifier != null && notifier.canUndo) {
      notifier.undo();
    }
  }

  void redo(int pageIndex) {
    final notifier = _pageNotifiers[pageIndex];
    if (notifier != null && notifier.canRedo) {
      notifier.redo();
    }
  }

  void clearPage(int pageIndex) {
    _pageNotifiers[pageIndex]?.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(flushNow());
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(flushNow());
    WidgetsBinding.instance.removeObserver(this);
    for (final notifier in _pageNotifiers.values) {
      notifier.removeListener(_onPageChanged);
      notifier.dispose();
    }
    super.dispose();
  }
}
