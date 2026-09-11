import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/library_entry.dart';
import '../services/storage_service.dart';

/// Owns the in-app PDF library: import, list, rename, delete, and tracking
/// which document was opened last.
class LibraryController extends ChangeNotifier {
  LibraryController(this._storage);

  final StorageService _storage;
  final List<LibraryEntry> _entries = [];
  bool _loading = true;

  bool get loading => _loading;

  List<LibraryEntry> get entries {
    final sorted = List<LibraryEntry>.of(_entries);
    sorted.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return List.unmodifiable(sorted);
  }

  Future<void> load() async {
    final raw = await _storage.readLibraryIndex();
    _entries
      ..clear()
      ..addAll(raw.map(LibraryEntry.fromJson));
    _loading = false;
    notifyListeners();
  }

  Future<LibraryEntry> importPdf(File pickedFile, {String? titleOverride}) async {
    final id = const Uuid().v4();
    final destFile = await _storage.sourcePdfFile(id);
    await pickedFile.copy(destFile.path);

    final document = await PdfDocument.openFile(destFile.path);
    final pageCount = document.pages.length;
    try {
      await _generateThumbnail(id, document);
    } catch (_) {
      // Thumbnail is a nice-to-have; import must still succeed without one.
    } finally {
      await document.dispose();
    }

    final now = DateTime.now();
    final title = titleOverride ?? p.basenameWithoutExtension(pickedFile.path);
    final entry = LibraryEntry(
      id: id,
      title: title,
      importedAt: now,
      lastOpenedAt: now,
      pageCount: pageCount,
    );
    _entries.add(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<void> touchOpened(String id) async {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    _entries[index].lastOpenedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> renameEntry(String id, String newTitle) async {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    _entries[index].title = trimmed;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _storage.deleteDocument(id);
    await _persist();
    notifyListeners();
  }

  Future<File> sourcePdfFile(String id) => _storage.sourcePdfFile(id);

  Future<File?> thumbnailFileIfExists(String id) async {
    final file = await _storage.thumbnailFile(id);
    return await file.exists() ? file : null;
  }

  Future<void> _persist() => _storage.writeLibraryIndex(_entries.map((e) => e.toJson()).toList());

  Future<void> _generateThumbnail(String id, PdfDocument document) async {
    if (document.pages.isEmpty) return;
    final page = document.pages.first;
    const maxDim = 360.0;
    final scale = maxDim / (page.width > page.height ? page.width : page.height);
    final width = (page.width * scale).round().clamp(1, 4096);
    final height = (page.height * scale).round().clamp(1, 4096);

    final image = await page.render(fullWidth: width.toDouble(), fullHeight: height.toDouble());
    if (image == null) return;
    try {
      final pngBytes = await _bgraToPng(image.pixels, image.width, image.height);
      final thumbFile = await _storage.thumbnailFile(id);
      await thumbFile.writeAsBytes(pngBytes, flush: true);
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> _bgraToPng(Uint8List bgra, int width, int height) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bgra,
      width,
      height,
      ui.PixelFormat.bgra8888,
      (image) => completer.complete(image),
    );
    final image = await completer.future;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
