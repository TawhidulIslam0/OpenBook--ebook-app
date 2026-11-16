double calculatePublicationProgress({
  required int spineItemIndex,
  required List<int> pageCounts,
  required double? spineProgression,
  required double fallbackProgress,
}) {
  final totalPages = pageCounts.fold<int>(
    0,
    (total, count) => total + (count > 0 ? count : 0),
  );
  if (totalPages == 0 ||
      spineItemIndex < 0 ||
      spineItemIndex >= pageCounts.length) {
    return fallbackProgress.clamp(0.0, 1.0).toDouble();
  }

  final pagesBefore = pageCounts
      .take(spineItemIndex)
      .fold<int>(0, (total, count) => total + (count > 0 ? count : 0));
  final localProgress =
      (spineProgression ?? fallbackProgress).clamp(0.0, 1.0).toDouble();
  return ((pagesBefore + pageCounts[spineItemIndex] * localProgress) /
          totalPages)
      .clamp(0.0, 1.0)
      .toDouble();
}
