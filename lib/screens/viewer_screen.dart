import 'package:flutter/gestures.dart';
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

  // In "Parmak" (finger-draw) mode, Scribble's overlay captures every touch
  // pointer for drawing, which blocks pdfrx's own pinch/pan gesture handling.
  // We track raw touch pointers here so a 2-finger touch can still pan/zoom
  // the page even while single-finger touches are reserved for drawing.
  final Map<int, Offset> _activeTouchPoints = {};
  double? _lastPinchDistance;
  Offset? _lastPinchFocal;

  // Tracks the stylus' barrel-button bitmask so we can detect a fresh press
  // (rising edge) instead of re-triggering on every event while held.
  int _lastStylusButtons = 0;
  // The primary button is a *temporary* hold (matches a real eraser): while
  // held we force eraser mode, and on release we restore whatever tool was
  // active before the press. A permanent toggle here is what made drawing
  // feel "stuck" — a stray brush of the button mid-stroke would leave you
  // erasing indefinitely with no obvious way back.
  bool _stylusButtonHeld = false;
  bool _eraserStateBeforeHold = false;

  bool _stylusDetected = false;
  bool _stylusIntroDismissed = false;

  // PdfViewerController.value throws until pdfrx has actually attached its
  // internal state to the controller, which happens asynchronously after the
  // document loads — so the zoom chip (which reads .value) must wait for
  // this instead of mounting alongside the viewer.
  bool _pdfReady = false;

  final List<Color> _customColors = [];
  static const _maxCustomColors = 4;
  static const _customColorChoices = <Color>[
    Color(0xFFF57C00), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFF00897B), // teal
    Color(0xFFD81B60), // pink
    Color(0xFF6D4C41), // brown
    Color(0xFFFDD835), // yellow
    Color(0xFF00ACC1), // cyan
    Color(0xFF546E7A), // blue-grey
  ];

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

  void _toggleEraser() {
    setState(() => _eraserActive = !_eraserActive);
    _annotationController.setEraserActive(_currentPageIndex, _eraserActive);
  }

  void _returnToPen() {
    if (!_eraserActive) return;
    setState(() => _eraserActive = false);
    _annotationController.setColor(_annotationController.selectedColor);
  }

  void _handleTouchDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _activeTouchPoints[event.pointer] = event.localPosition;
      _lastPinchDistance = null;
      _lastPinchFocal = null;
    }
    _checkStylusButtons(event);
  }

  void _handleTouchMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch && _activeTouchPoints.containsKey(event.pointer)) {
      _activeTouchPoints[event.pointer] = event.localPosition;
      _updatePinchZoom();
    }
    _checkStylusButtons(event);
  }

  void _handleTouchEnd(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _activeTouchPoints.remove(event.pointer);
      _lastPinchDistance = null;
      _lastPinchFocal = null;
    }
    // The tip lifting or the pointer being cancelled is also the safest
    // moment to guarantee the temporary eraser hold ends, even if the
    // hardware never reports a clean button-release event for it.
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      _releaseStylusHold();
      _lastStylusButtons = 0;
    }
    _checkStylusButtons(event);
  }

  void _handleStylusHover(PointerHoverEvent event) {
    _checkStylusButtons(event);
  }

  /// The pen's barrel buttons are only reported through raw [PointerEvent]s,
  /// not through Scribble's drawing logic, so we watch them here and diff
  /// against the previously seen state to fire only on a fresh press (not on
  /// every event while a button stays held).
  void _checkStylusButtons(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus && event.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    if (!_stylusDetected) {
      setState(() => _stylusDetected = true);
    }
    final pressedNow = event.buttons & ~_lastStylusButtons;
    final releasedNow = _lastStylusButtons & ~event.buttons;

    if (pressedNow & kPrimaryStylusButton != 0 && !_stylusButtonHeld) {
      _stylusButtonHeld = true;
      _eraserStateBeforeHold = _eraserActive;
      if (!_eraserActive) {
        setState(() => _eraserActive = true);
        _annotationController.setEraserActive(_currentPageIndex, true);
      }
    }
    if (releasedNow & kPrimaryStylusButton != 0) {
      _releaseStylusHold();
    }
    if (pressedNow & kSecondaryStylusButton != 0) {
      _returnToPen();
    }
    _lastStylusButtons = event.buttons;
  }

  /// Ends the primary button's temporary eraser hold and restores whatever
  /// tool was active right before it was pressed.
  void _releaseStylusHold() {
    if (!_stylusButtonHeld) return;
    _stylusButtonHeld = false;
    if (_eraserActive == _eraserStateBeforeHold) return;
    setState(() => _eraserActive = _eraserStateBeforeHold);
    if (_eraserStateBeforeHold) {
      _annotationController.setEraserActive(_currentPageIndex, true);
    } else {
      _annotationController.setColor(_annotationController.selectedColor);
    }
  }

  /// Manually drives 2-finger pinch-zoom + pan while in "Parmak" mode, where
  /// Scribble owns every touch pointer and pdfrx's built-in InteractiveViewer
  /// never sees them. In "Kalem" mode this is a no-op: fingers already pass
  /// straight through to pdfrx's native pinch/pan since only the stylus is
  /// captured for drawing.
  void _updatePinchZoom() {
    if (_annotationController.stylusOnly) return;
    if (_activeTouchPoints.length != 2) return;

    final points = _activeTouchPoints.values.toList(growable: false);
    final p1 = points[0];
    final p2 = points[1];
    final distance = (p1 - p2).distance;
    final focal = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

    if (_lastPinchDistance == null || _lastPinchFocal == null) {
      _lastPinchDistance = distance;
      _lastPinchFocal = focal;
      return;
    }

    final matrix = _pdfController.value;
    final zoom = matrix.zoom;
    final scaleDelta = distance / _lastPinchDistance!.clamp(1.0, double.infinity);
    final newZoom = (zoom * scaleDelta).clamp(0.5, 8.0);

    // Keep the document point that was under the previous focal point
    // anchored under the new focal point, so the pinch feels natural.
    final focalDoc = Offset(
      (_lastPinchFocal!.dx - matrix.xZoomed) / zoom,
      (_lastPinchFocal!.dy - matrix.yZoomed) / zoom,
    );

    final newMatrix = Matrix4.identity()
      ..storage[0] = newZoom
      ..storage[5] = newZoom
      ..storage[10] = newZoom
      ..storage[12] = -focalDoc.dx * newZoom + focal.dx
      ..storage[13] = -focalDoc.dy * newZoom + focal.dy;

    _pdfController.value = newMatrix;

    _lastPinchDistance = distance;
    _lastPinchFocal = focal;
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
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _handleTouchDown,
                          onPointerMove: _handleTouchMove,
                          onPointerUp: _handleTouchEnd,
                          onPointerCancel: _handleTouchEnd,
                          onPointerHover: _handleStylusHover,
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
                              onViewerReady: (document, controller) {
                                if (mounted) setState(() => _pdfReady = true);
                              },
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
                      ),
                      Positioned(left: 0, right: 0, bottom: 22, child: Center(child: _buildToolbar())),
                      if (_pdfReady) Positioned(right: 20, bottom: 108, child: _buildZoomChip()),
                      if (_stylusDetected && !_stylusIntroDismissed)
                        Positioned(
                          left: 40,
                          bottom: 108,
                          child: _StylusIntroCard(
                            onDismiss: () => setState(() => _stylusIntroDismissed = true),
                          ),
                        ),
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
                    for (final color in _customColors) _colorSwatch(color, removable: true),
                    _addColorButton(),
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
                      onPressed: _toggleEraser,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildZoomChip() {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _pdfController,
      builder: (context, matrix, _) {
        final percent = (matrix.zoom * 100).round();
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.borderToolbar),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_in, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                '%$percent · iki parmakla yakınlaştır',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ],
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

  Widget _colorSwatch(Color color, {bool removable = false}) {
    final selected = _annotationController.selectedColor == color && !_eraserActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () {
          setState(() => _eraserActive = false);
          _annotationController.setColor(color);
        },
        onLongPress: removable
            ? () {
                setState(() => _customColors.remove(color));
              }
            : null,
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

  Widget _addColorButton() {
    final count = _customColors.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: _showCustomColorPicker,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderCard, style: BorderStyle.solid),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add, size: 16, color: AppColors.textSecondary),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomColorPicker() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renk ekle'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in _customColorChoices)
                InkWell(
                  onTap: () => Navigator.pop(context, color),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _customColors.contains(color) ? AppColors.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (_customColors.contains(picked)) {
      setState(() => _customColors.remove(picked));
      return;
    }
    setState(() {
      if (_customColors.length >= _maxCustomColors) {
        _customColors.removeAt(0);
      }
      _customColors.add(picked);
      _eraserActive = false;
    });
    _annotationController.setColor(picked);
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

class _StylusIntroCard extends StatelessWidget {
  const _StylusIntroCard({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderHeader),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Kalem tuşları', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buttonRow(number: '1', label: 'Alt tuş', actionLabel: 'Silgi'),
          const SizedBox(height: 8),
          _buttonRow(number: '2', label: 'Üst tuş', actionLabel: 'Kaleme dön'),
          const SizedBox(height: 10),
          const Text(
            'Basılı tut: silgiye geçici geçiş, bırakınca kaleme döner.',
            style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buttonRow({required String number, required String label, required String actionLabel}) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppColors.thumbFill, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderToolbar),
            ),
            alignment: Alignment.center,
            child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppColors.accentContainer, borderRadius: BorderRadius.circular(999)),
            alignment: Alignment.center,
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.onAccentContainer),
            ),
          ),
        ],
      ),
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
