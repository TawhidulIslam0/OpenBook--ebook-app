import 'package:flutter_test/flutter_test.dart';
import 'package:iridium_reader_widget/views/viewers/reader_progress.dart';

void main() {
  test('weights chapter progress by its share of the book', () {
    expect(
      calculatePublicationProgress(
        spineItemIndex: 1,
        pageCounts: [10, 30],
        spineProgression: 0.5,
        fallbackProgress: 0,
      ),
      0.625,
    );
  });

  test('uses fallback progress when chapter progression is unavailable', () {
    expect(
      calculatePublicationProgress(
        spineItemIndex: 0,
        pageCounts: [10, 30],
        spineProgression: null,
        fallbackProgress: 0.5,
      ),
      0.125,
    );
  });

  test('clamps invalid progress and falls back for missing page counts', () {
    expect(
      calculatePublicationProgress(
        spineItemIndex: 4,
        pageCounts: [10],
        spineProgression: 1.5,
        fallbackProgress: 1.5,
      ),
      1,
    );
    expect(
      calculatePublicationProgress(
        spineItemIndex: 0,
        pageCounts: [0],
        spineProgression: 0.5,
        fallbackProgress: -0.5,
      ),
      0,
    );
  });
}
