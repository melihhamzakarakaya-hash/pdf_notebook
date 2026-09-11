import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../models/library_entry.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import 'viewer_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _importing = false;
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<LibraryController>().load();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importPdf() async {
    final picked = await FilePickerPlatform.instance.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    final library = context.read<LibraryController>();

    setState(() => _importing = true);
    try {
      final entry = await library.importPdf(File(path));
      if (mounted) _openEntry(entry);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF içe aktarılamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openEntry(LibraryEntry entry) async {
    await context.read<LibraryController>().touchOpened(entry.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ViewerScreen(entry: entry)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _rename(LibraryEntry entry) async {
    final controller = TextEditingController(text: entry.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeniden adlandır'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (newTitle != null && mounted) {
      await context.read<LibraryController>().renameEntry(entry.id, newTitle);
    }
  }

  Future<void> _delete(LibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF silinsin mi?'),
        content: Text('"${entry.title}" ve üzerindeki tüm çözümler kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<LibraryController>().deleteEntry(entry.id);
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _searchController.clear();
    });
  }

  Widget _addButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _importing ? null : _importPdf,
      child: Container(
        height: 48,
        padding: const EdgeInsets.only(left: 18, right: 22),
        decoration: BoxDecoration(
          color: AppColors.accentContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccentContainer),
                  )
                : const Icon(Icons.add, color: AppColors.onAccentContainer, size: 20),
            const SizedBox(width: 9),
            Text(
              _importing ? 'İçe aktarılıyor...' : 'PDF Ekle',
              style: const TextStyle(color: AppColors.onAccentContainer, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        titleSpacing: 28,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Defterlerde ara...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                ),
                style: const TextStyle(fontSize: 18, color: AppColors.textPrimary),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.description_outlined, color: AppColors.iconBadgeStroke, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Consumer<LibraryController>(
                    builder: (context, library, _) {
                      final total = library.entries.length;
                      final thisWeek = library.entries
                          .where((e) => DateTime.now().difference(e.importedAt).inDays < 7)
                          .length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'PDF Defterim',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                          ),
                          if (total > 0)
                            Text(
                              '$total defter${thisWeek > 0 ? ' · $thisWeek tanesi bu hafta' : ''}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Aramayı kapat' : 'Ara',
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(right: 8), child: _addButton()),
        ],
      ),
      body: Consumer<LibraryController>(
        builder: (context, library, _) {
          if (library.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (library.entries.isEmpty) {
            return _EmptyLibrary(onImport: _importing ? null : _importPdf, importing: _importing);
          }
          final query = _searchController.text.trim().toLowerCase();
          final entries = query.isEmpty
              ? library.entries
              : library.entries.where((e) => e.title.toLowerCase().contains(query)).toList();
          final mostRecent = library.entries.first;

          if (entries.isEmpty) {
            return Center(
              child: Text('"$query" için sonuç bulunamadı', style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: 0.68,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final showBadge = entry.id == mostRecent.id &&
                  DateTime.now().difference(entry.lastOpenedAt).inHours < 24;
              return _LibraryCard(
                entry: entry,
                showBadge: showBadge,
                onTap: () => _openEntry(entry),
                onRename: () => _rename(entry),
                onDelete: () => _delete(entry),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport, required this.importing});

  final VoidCallback? onImport;
  final bool importing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 168,
              height: 168,
              decoration: const BoxDecoration(
                color: AppColors.emptyIconBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_outlined, size: 72, color: AppColors.primary),
            ),
            const SizedBox(height: 26),
            const Text(
              'Defterin henüz boş',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Soru kağıdı PDF\'ini içe aktar, sayfaların üzerine kalemle çözümünü yaz. Notların PDF ile birlikte saklanır.',
              style: TextStyle(fontSize: 15.5, height: 1.5, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onImport,
              child: Container(
                height: 56,
                padding: const EdgeInsets.only(left: 24, right: 30),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.32), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add, color: Colors.white),
                    const SizedBox(width: 11),
                    Text(
                      importing ? 'İçe aktarılıyor...' : 'İlk PDF\'ini ekle',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('veya dosyayı buraya sürükle', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.entry,
    required this.showBadge,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryEntry entry;
  final bool showBadge;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  Color _placeholderColor() {
    final index = entry.id.hashCode.abs() % AppColors.cardPlaceholderTints.length;
    return AppColors.cardPlaceholderTints[index].withValues(alpha: 0.35);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryController>();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderCard),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<File?>(
                    future: library.thumbnailFileIfExists(entry.id),
                    builder: (context, snapshot) {
                      final file = snapshot.data;
                      if (file == null) {
                        return _PaperPlaceholder(tint: _placeholderColor());
                      }
                      return Image.file(file, fit: BoxFit.cover, width: double.infinity);
                    },
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      child: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') onRename();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: _MenuRow(icon: Icons.edit_outlined, label: 'Yeniden adlandır'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: _MenuRow(icon: Icons.delete_outline, label: 'Sil', color: AppColors.error),
                          ),
                        ],
                        icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          color: AppColors.accentContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Devam ediyor',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onAccentContainer),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.pageCount} sayfa · ${formatRelativeTime(entry.lastOpenedAt)} açıldı',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 20, color: effectiveColor),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: effectiveColor)),
      ],
    );
  }
}

/// Faux ruled-paper look shown while a real page thumbnail hasn't been
/// generated yet (e.g. mid-import).
class _PaperPlaceholder extends StatelessWidget {
  const _PaperPlaceholder({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.thumbFill,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.borderMuted),
            left: BorderSide(color: AppColors.borderMuted),
            right: BorderSide(color: AppColors.borderMuted),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 5, width: 44, color: AppColors.thumbLine, margin: const EdgeInsets.only(bottom: 6)),
            for (final w in [1.0, 0.92, 0.74, 0.96, 0.66])
              Container(
                height: 3,
                width: 62 * w,
                color: AppColors.thumbLineFaint,
                margin: const EdgeInsets.only(bottom: 4),
              ),
          ],
        ),
      ),
    );
  }
}
