import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_ebook_app/src/features/explore/data/repositories/explore_repository.dart';
import 'package:flutter_ebook_app/src/features/explore/presentation/notifiers/genre_feed/genre_feed_notifier.dart';
import 'package:flutter_ebook_app/src/features/explore/presentation/ui/screens/explore_screen_small.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads Explore shelves as they enter view', (tester) async {
    final links = List.generate(
      10,
      (index) => Link(
        title: 'Genre $index',
        href: 'https://gutendex.com/books/?topic=genre-$index',
      ),
    );
    final repository = _CountingExploreRepository();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exploreFeedProvider.overrideWith(
            (ref) async => CategoryFeed(feed: Feed(link: links)),
          ),
          exploreRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const MaterialApp(home: ExploreScreenSmall()),
      ),
    );

    await tester.pumpAndSettle();
    final initialRequests = repository.startedRequests;
    expect(initialRequests, greaterThan(0));
    expect(initialRequests, lessThan(links.length));

    await tester.scrollUntilVisible(
      find.text('Genre ${links.length - 1}'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(repository.startedRequests, links.length);
  });

  test('Genre See All follows the API next-page link', () async {
    const url =
        'https://gutendex.com/books/?languages=en&copyright=false&topic=adventure';
    final repository = _PagedExploreRepository();
    final provider = genreFeedNotifierProvider(url);
    final container = ProviderContainer(
      overrides: [exploreRepositoryProvider.overrideWith((ref) => repository)],
    );
    final subscription = container.listen(provider, (previous, next) {});
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final firstPage = await container.read(provider.future);
    expect(firstPage.books.map((book) => book.id?.t), ['1']);
    expect(firstPage.hasMore, isTrue);

    await container.read(provider.notifier).paginate(2);
    final allBooks = container.read(provider).requireValue;
    expect(allBooks.books.map((book) => book.id?.t), ['1', '2']);
    expect(allBooks.hasMore, isFalse);
  });
}

class _CountingExploreRepository extends ExploreRepository {
  _CountingExploreRepository() : super(Dio());

  int startedRequests = 0;

  @override
  Future<BookRepositoryData> getGenreFeed(String url) async {
    startedRequests++;
    return (
      feed: CategoryFeed(
        feed: Feed(link: [], entry: []),
      ),
      failure: null,
    );
  }
}

class _PagedExploreRepository extends ExploreRepository {
  _PagedExploreRepository() : super(Dio());

  @override
  Future<BookRepositoryData> getGenreFeed(String url) async {
    final page = Uri.parse(url).queryParameters['page'];
    final isFirstPage = page == null || page == '1';
    return (
      feed: CategoryFeed(
        feed: Feed(
          entry: [Entry(id: Id(t: isFirstPage ? '1' : '2'))],
          link: [
            if (isFirstPage)
              Link(rel: 'next', href: 'https://gutendex.com/books/?page=2'),
          ],
        ),
      ),
      failure: null,
    );
  }
}
