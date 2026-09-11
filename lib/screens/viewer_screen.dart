import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:scribble/scribble.dart';

import '../controllers/document_annotation_controller.dart';
import '../controllers/library_controller.dart';
import '../models/library_entry.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final DocumentAnnotationController _annotationController;
  late final Future<String> _initFuture;
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPageIndex = 0;
  bool _eraserActive = false;

  static const _penColors = AppColors.penColors;
  static const _penWidths = <double>[2, 4, 8];

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _annotationController = DocumentAnnotationController(
      documentId: widget.entry.id,
      storage: storage,
    );
    final libraryController = context.read<LibraryController>();
    _initFuture = () async {
      await _annotationController.load();
      final file = await libraryController.sourcePdfFile(widget.entry.id);
      return file.path;
    }();
  }

  @override
  void dispose() {
    _annotationController.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    await _annotationController.flushNow();
    return true;
  }

  void _goToPage(int pageIndex) {
    final clamped = pageIndex.clamp(0, widget.entry.pageCount - 1);
    _pdfController.goToPage(pageNumber: clamped + 1);
  }

  Future<void> _jumpToPageDialog() async {
    final controller = TextEditingController(text: '${_currentPageIndex + 1}');
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sayfaya git'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: '1 - ${widget.entry.pageCount} arası'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Git'),
          ),
        ],
      ),
    );
    if (target != null) _goToPage(target - 1);
  }

  Future<void> _showPageOverview() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sayfalar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < widget.entry.pageCount; i++)
                          _PageChip(
                            pageNumber: i + 1,
                            selected: i == _currentPageIndex,
                            onTap: () => Navigator.pop(context, i),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (target != null) _goToPage(target);
  }

  Future<void> _renameDocument() async {
    final controller = TextEditingController(text: widget.entry.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeniden adlandır'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (newTitle != null && mounted) {
      await context.read<LibraryController>().renameEntry(widget.entry.id, newTitle);
      setState(() => widget.entry.title = newTitle.trim().isEmpty ? widget.entry.title : newTitle.trim());
    }
  }

  Future<void> _clearCurrentPage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sayfa temizlensin mi?'),
        content: Text('${_currentPageIndex + 1}. sayfadaki tüm çizimler silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _annotationController.clearPage(_currentPageIndex);
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF silinsin mi?'),
        content: Text('"${widget.entry.title}" ve üzerindeki tüm çözümler kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
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
      await context.read<LibraryController>().deleteEntry(widget.entry.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _handleBack();
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.viewerBody,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FutureBuilder<String>(
                future: _initFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('PDF açılamadı: ${snapshot.error}'));
                  }
                  final sourcePath = snapshot.data!;
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.borderPaper),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          clipBehavior: Clip.antiAlias,
                          child: PdfViewer.file(
                            sourcePath,
                            controller: _pdfController,
                            params: PdfViewerParams(
                              backgroundColor: AppColors.surface,
                              onPageChanged: (pageNumber) {
                                if (pageNumber == null) return;
                                setState(() => _currentPageIndex = pageNumber - 1);
                              },
                              pageOverlaysBuilder: (context, pageRect, page) {
                                final pageIndex = page.pageNumber - 1;
                                return [
                                  SizedBox(
                                    width: pageRect.width,
                                    height: pageRect.height,
                                    child: FittedBox(
                                      fit: BoxFit.fill,
                                      child: SizedBox(
                                        width: page.width,
                                        height: page.height,
                                        child: Scribble(
                                          notifier: _annotationController.notifierForPage(pageIndex),
                                        ),
                                      ),
                                    ),
                                  ),
                                ];
                              },
                            ),
                          ),
                        ),
                      ),
                      Positioned(left: 0, right: 0, bottom: 22, child: Center(child: _buildToolbar())),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDim,
        border: Border(bottom: BorderSide(color: AppColors.borderHeader)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Geri',
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
                  onPressed: () async {
                    await _handleBack();
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _annotationController,
                    builder: (context, _) {
                      final savedAt = _annotationController.lastSavedAt;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          if (savedAt != null)
                            Text(
                              'Otomatik kaydedildi · ${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Önceki sayfa',
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPageIndex > 0 ? () => _goToPage(_currentPageIndex - 1) : null,
              ),
              InkWell(
                onTap: _jumpToPageDialog,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppColors.accentContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_currentPageIndex + 1} / ${widget.entry.pageCount}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onAccentContainer),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.expand_more, size: 16, color: AppColors.onAccentContainer),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sonraki sayfa',
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPageIndex < widget.entry.pageCount - 1 ? () => _goToPage(_currentPageIndex + 1) : null,
              ),
            ],
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Sayfalar',
                  icon: const Icon(Icons.grid_view_outlined),
                  onPressed: _showPageOverview,
                ),
                IconButton(
                  tooltip: 'Dışa aktar',
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dışa aktarma yakında geliyor')),
                    );
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Diğer',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'rename') _renameDocument();
                    if (value == 'clear') _clearCurrentPage();
                    if (value == 'delete') _deleteDocument();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: _MenuRow(icon: Icons.edit_outlined, label: 'Yeniden adlandır')),
                    PopupMenuItem(value: 'clear', child: _MenuRow(icon: Icons.layers_clear_outlined, label: 'Sayfayı temizle')),
                    PopupMenuItem(value: 'delete', child: _MenuRow(icon: Icons.delete_outline, label: 'Sil', color: AppColors.error)),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return ListenableBuilder(
      listenable: _annotationController,
      builder: (context, _) {
        return Material(
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(26),
          color: AppColors.surface,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.borderToolbar),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toolGroup([
                    for (final color in _penColors) _colorSwatch(color),
                  ]),
                  _groupDivider(),
                  _toolGroup([
                    for (final width in _penWidths) _widthButton(width),
                  ]),
                  _groupDivider(),
                  _toolGroup([
                    _toolbarIcon(
                      tooltip: 'Silgi',
                      icon: _eraserActive ? Icons.auto_fix_high : Icons.auto_fix_normal,
                      selected: _eraserActive,
                      onPressed: () {
                        setState(() => _eraserActive = !_eraserActive);
                        _annotationController.setEraserActive(_currentPageIndex, _eraserActive);
                      },
                    ),
                    _toolbarIcon(
                      tooltip: 'Geri al',
                      icon: Icons.undo,
                      onPressed: () => _annotationController.undo(_currentPageIndex),
                    ),
                    _toolbarIcon(
                      tooltip: 'Yinele',
                      icon: Icons.redo,
                      onPressed: () => _annotationController.redo(_currentPageIndex),
                    ),
                  ]),
                  _groupDivider(),
                  _toolGroup([
                    _modeSegment(
                      label: 'Kalem',
                      icon: Icons.edit,
                      selected: _annotationController.stylusOnly,
                      onTap: () => _annotationController.setStylusOnly(true),
                    ),
                    _modeSegment(
                      label: 'Parmak',
                      icon: Icons.touch_app,
                      selected: !_annotationController.stylusOnly,
                      onTap: () => _annotationController.setStylusOnly(false),
                    ),
                  ]),
                  _groupDivider(),
                  _toolGroup([
                    _toolbarIcon(
                      tooltip: 'Yakınlaştır',
                      icon: Icons.zoom_in,
                      onPressed: () => _pdfController.zoomUp(loop: true),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _toolGroup(List<Widget> children) {
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _groupDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: VerticalDivider(width: 1, thickness: 1, color: AppColors.borderHeader),
    );
  }

  Widget _toolbarIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        color: selected ? AppColors.onAccentContainer : AppColors.textSecondary,
        style: IconButton.styleFrom(
          backgroundColor: selected ? AppColors.accentContainer : null,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _modeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentContainer : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.onAccentContainer : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.onAccentContainer : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorSwatch(Color color) {
    final selected = _annotationController.selectedColor == color && !_eraserActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () {
          setState(() => _eraserActive = false);
          _annotationController.setColor(color);
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentContainer : null,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _widthButton(double width) {
    final selected = _annotationController.selectedWidth == width;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => _annotationController.setStrokeWidth(width),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppColors.accentContainer : null,
          ),
          child: Container(
            width: width * 1.6,
            height: width * 1.6,
            decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
          ),
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

class _PageChip extends StatelessWidget {
  const _PageChip({required this.pageNumber, required this.selected, required this.onTap});

  final int pageNumber;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentContainer : AppColors.surfaceDim,
          border: Border.all(color: selected ? AppColors.primary : AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$pageNumber',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onAccentContainer : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
