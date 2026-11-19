import 'package:all_docs/services/text_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses native OCR output and drops empty or tiny lines', () {
    final result = parseRecognizedText({
      'text': ' Fatura 12\nTotal ',
      'lines': [
        {
          'text': 'Fatura   12',
          'left': 10,
          'top': 20,
          'width': 200,
          'height': 30,
        },
        {'text': '  ', 'left': 0, 'top': 0, 'width': 50, 'height': 10},
        {'text': '.', 'left': 0, 'top': 0, 'width': 1, 'height': 10},
        {'text': 'Total', 'left': 10.5, 'top': 60, 'width': 80, 'height': 28},
      ],
    });

    expect(result.text, 'Fatura 12\nTotal');
    expect(result.lines.map((l) => l.text), ['Fatura 12', 'Total']);
    expect(result.lines.last.left, 10.5);
  });

  test('missing fields read as no text', () {
    final result = parseRecognizedText(const {});
    expect(result.text, isEmpty);
    expect(result.lines, isEmpty);
  });
}
