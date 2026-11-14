import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_ebook_app/src/features/features.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_feed_notifier.g.dart';

typedef HomeFeedData = ({
  CategoryFeed popularFeed,
  CategoryFeed recentFeed,
  bool recentLoading,
  String? recentError,
});

@riverpod
class HomeFeedNotifier extends _$HomeFeedNotifier {
  HomeFeedNotifier() : super();

  int _requestGeneration = 0;
  bool _disposed = false;

  @override
  Future<HomeFeedData> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return _fetch(++_requestGeneration);
  }

  Future<void> fetch() async {
    final generation = ++_requestGeneration;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch(generation));
  }

  Future<HomeFeedData> _fetch(int generation) async {
    final HomeRepository homeRepository = ref.read(homeRepositoryProvider);
    final popularFuture = _getPopularFeed(homeRepository);
    final recentFuture = _getRecentFeed(homeRepository);
    final popularResponse = popularFuture.then(
      (result) => (isPopular: true, result: result),
    );
    final recentResponse = recentFuture.then(
      (result) => (isPopular: false, result: result),
    );

    var firstResponse = await Future.any([popularResponse, recentResponse]);
    if (firstResponse.result?.feed == null) {
      final otherResponse =
          await (firstResponse.isPopular ? recentResponse : popularResponse);
      if (otherResponse.result?.feed == null) {
        final failure =
            otherResponse.result?.failure ?? firstResponse.result?.failure;
        throw failure?.description ?? 'Could not load the home book feeds.';
      }
      firstResponse = otherResponse;
    }

    final firstFeed = firstResponse.result!.feed!;
    if (firstResponse.isPopular) {
      unawaited(_applyRecentFeed(recentFuture, generation, firstFeed));
      return (
        popularFeed: firstFeed,
        recentFeed: CategoryFeed(),
        recentLoading: true,
        recentError: null,
      );
    }

    final emptyPopularFeed = CategoryFeed(
      feed: Feed(link: firstFeed.feed?.link, entry: []),
    );
    unawaited(_applyPopularFeed(popularFuture, generation, emptyPopularFeed));
    return (
      popularFeed: emptyPopularFeed,
      recentFeed: firstFeed,
      recentLoading: false,
      recentError: null,
    );
  }

  Future<BookRepositoryData?> _getPopularFeed(
    HomeRepository homeRepository,
  ) async {
    try {
      return await homeRepository.getPopularHomeFeed();
    } catch (error, stackTrace) {
      debugPrint('Could not load popular books: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<BookRepositoryData?> _getRecentFeed(
    HomeRepository homeRepository,
  ) async {
    try {
      return await homeRepository.getRecentHomeFeed();
    } catch (error, stackTrace) {
      debugPrint('Could not load recently added books: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _applyRecentFeed(
    Future<BookRepositoryData?> recentFuture,
    int generation,
    CategoryFeed popularFeed,
  ) async {
    try {
      final recentResult = await recentFuture;
      if (_disposed || generation != _requestGeneration) return;
      final recentFeed = recentResult?.feed;
      if (recentFeed == null) {
        if (recentResult != null) {
          debugPrint(
            'Recently added books could not be loaded: '
            '${recentResult.failure?.description ?? 'No recent feed returned.'}',
          );
        }
        final current = state.asData?.value;
        if (current != null && identical(current.popularFeed, popularFeed)) {
          state = AsyncValue.data(
            (
              popularFeed: current.popularFeed,
              recentFeed: current.recentFeed,
              recentLoading: false,
              recentError: recentResult?.failure?.description ??
                  'Recently added books could not be loaded.',
            ),
          );
        }
        return;
      }

      final current = state.asData?.value;
      if (current == null || !identical(current.popularFeed, popularFeed)) {
        return;
      }
      state = AsyncValue.data(
        (
          popularFeed: current.popularFeed,
          recentFeed: recentFeed,
          recentLoading: false,
          recentError: null,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not load recently added books: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _applyPopularFeed(
    Future<BookRepositoryData?> popularFuture,
    int generation,
    CategoryFeed fallbackFeed,
  ) async {
    try {
      final popularResult = await popularFuture;
      if (_disposed || generation != _requestGeneration) return;
      final popularFeed = popularResult?.feed;
      if (popularFeed == null) {
        debugPrint(
          'Popular books could not be loaded: '
          '${popularResult?.failure?.description ?? 'No popular feed returned.'}',
        );
        return;
      }

      final current = state.asData?.value;
      if (current == null || !identical(current.popularFeed, fallbackFeed)) {
        return;
      }
      state = AsyncValue.data(
        (
          popularFeed: popularFeed,
          recentFeed: current.recentFeed,
          recentLoading: current.recentLoading,
          recentError: current.recentError,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not load popular books: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
