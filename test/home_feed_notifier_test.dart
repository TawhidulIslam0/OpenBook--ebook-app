import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_ebook_app/src/features/home/data/repositories/home_repository.dart';
import 'package:flutter_ebook_app/src/features/home/presentation/notifiers/home_feed_notifier.dart';
import 'package:flutter_ebook_app/src/features/home/presentation/ui/screens/home_screen_small.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the original Home section layout', (tester) async {
    final repository = _ReadyHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWith((ref) => repository)],
        child: const MaterialApp(home: HomeScreenSmall()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Featured'), findsNothing);
    expect(find.text('See All'), findsNothing);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
  });

  test('shows popular books before the recent feed finishes loading', () async {
    final recentFeed = Completer<BookRepositoryData>();
    final repository = _DelayedRecentHomeRepository(recentFeed);
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWith((ref) => repository)],
    );
    final subscription = container.listen(
      homeFeedNotifierProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final initialData = await container.read(homeFeedNotifierProvider.future);

    expect(initialData.popularFeed, same(repository.popularFeed));
    expect(initialData.recentFeed.feed, isNull);
    expect(initialData.recentLoading, isTrue);
    expect(repository.popularRequestCount, 1);
    expect(repository.recentRequestCount, 1);

    recentFeed.complete((feed: repository.recentFeed, failure: null));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedData = container.read(homeFeedNotifierProvider).requireValue;
    expect(loadedData.recentFeed, same(repository.recentFeed));
    expect(loadedData.recentLoading, isFalse);
  });

  test('shows recent books without waiting for the popular feed', () async {
    final popularFeed = Completer<BookRepositoryData>();
    final repository = _DelayedPopularHomeRepository(popularFeed);
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWith((ref) => repository)],
    );
    final subscription = container.listen(
      homeFeedNotifierProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final initialData = await container
        .read(homeFeedNotifierProvider.future)
        .timeout(const Duration(milliseconds: 500));

    expect(initialData.popularFeed.feed?.entry, isEmpty);
    expect(initialData.recentFeed, same(repository.recentFeed));
    expect(initialData.recentLoading, isFalse);
    expect(initialData.popularFeed.feed?.link, hasLength(1));

    popularFeed.complete((feed: repository.popularFeed, failure: null));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedData = container.read(homeFeedNotifierProvider).requireValue;
    expect(loadedData.popularFeed, same(repository.popularFeed));
    expect(loadedData.recentFeed, same(repository.recentFeed));
  });
}

class _DelayedRecentHomeRepository extends HomeRepository {
  _DelayedRecentHomeRepository(this.recentFeedCompleter) : super(Dio());

  final Completer<BookRepositoryData> recentFeedCompleter;
  final popularFeed = CategoryFeed(feed: Feed(entry: []));
  final recentFeed = CategoryFeed(feed: Feed(entry: []));
  int popularRequestCount = 0;
  int recentRequestCount = 0;

  @override
  Future<BookRepositoryData> getPopularHomeFeed() async {
    popularRequestCount++;
    return (feed: popularFeed, failure: null);
  }

  @override
  Future<BookRepositoryData> getRecentHomeFeed() {
    recentRequestCount++;
    return recentFeedCompleter.future;
  }
}

class _ReadyHomeRepository extends HomeRepository {
  _ReadyHomeRepository() : super(Dio());

  final feed = CategoryFeed(
    feed: Feed(entry: [], link: []),
  );

  @override
  Future<BookRepositoryData> getPopularHomeFeed() async {
    return (feed: feed, failure: null);
  }

  @override
  Future<BookRepositoryData> getRecentHomeFeed() async {
    return (feed: feed, failure: null);
  }
}

class _DelayedPopularHomeRepository extends HomeRepository {
  _DelayedPopularHomeRepository(this.popularFeedCompleter) : super(Dio());

  final Completer<BookRepositoryData> popularFeedCompleter;
  final popularFeed = CategoryFeed(feed: Feed(entry: []));
  final recentFeed = CategoryFeed(
    feed: Feed(
      entry: [],
      link: [
        Link(
          title: 'Adventure',
          href: 'https://gutendex.com/books/?topic=adventure',
        ),
      ],
    ),
  );

  @override
  Future<BookRepositoryData> getPopularHomeFeed() {
    return popularFeedCompleter.future;
  }

  @override
  Future<BookRepositoryData> getRecentHomeFeed() async {
    return (feed: recentFeed, failure: null);
  }
}
