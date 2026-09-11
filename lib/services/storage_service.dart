import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns all on-disk layout for the app: the library index and each
/// document's source PDF / stroke data / thumbnail, all rooted under the
/// app's private documents directory.
class StorageService {
  Directory? _appDir;

  Future<Directory> _getAppDir() async {
    return _appDir ??= await getApplicationDocumentsDirectory();
  }

  Future<Directory> _documentsRootDir() async {
    final appDir = await _getAppDir();
    final dir = Directory(p.join(appDir.path, 'documents'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> documentDir(String id) async {
    final root = await _documentsRootDir();
    final dir = Directory(p.join(root.path, id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> sourcePdfFile(String id) async {
    final dir = await documentDir(id);
    return File(p.join(dir.path, 'source.pdf'));
  }

  Future<File> strokesFile(String id) async {
    final dir = await documentDir(id);
    return File(p.join(dir.path, 'strokes.json'));
  }

  Future<File> thumbnailFile(String id) async {
    final dir = await documentDir(id);
    return File(p.join(dir.path, 'thumbnail.png'));
  }

  Future<File> _libraryIndexFile() async {
    final appDir = await _getAppDir();
    return File(p.join(appDir.path, 'library_index.json'));
  }

  Future<List<Map<String, dynamic>>> readLibraryIndex() async {
    final file = await _libraryIndexFile();
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      // Corrupt index: treat as empty rather than crashing the app.
      return [];
    }
  }

  Future<void> writeLibraryIndex(List<Map<String, dynamic>> entries) async {
    final file = await _libraryIndexFile();
    await _writeJsonAtomic(file, jsonEncode(entries));
  }

  Future<Map<String, dynamic>?> readStrokes(String id) async {
    final file = await strokesFile(id);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeStrokes(String id, Map<String, dynamic> pageIndexToSketchJson) async {
    final file = await strokesFile(id);
    await _writeJsonAtomic(file, jsonEncode(pageIndexToSketchJson));
  }

  Future<void> deleteDocument(String id) async {
    final dir = await documentDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Writes to a temp file then renames over the target, so a crash mid-write
  /// can never leave a corrupt/partial JSON file behind.
  Future<void> _writeJsonAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(target.path);
  }
}
