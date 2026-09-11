import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_notebook/main.dart';

void main() {
  testWidgets('App launches to the library screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfNotebookApp());
    await tester.pump();

    expect(find.text('PDF Kütüphanem'), findsOneWidget);
  });
}
