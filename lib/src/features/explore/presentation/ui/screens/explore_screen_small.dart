import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_ebook_app/src/features/features.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final exploreFeedProvider =
    FutureProvider.autoDispose<CategoryFeed>((ref) async {
  final repository = ref.watch(exploreRepositoryProvider);
  final result = await repository.getGenreFeed(popular);
  if (result.feed == null) {
    throw result.failure?.description ?? 'Could not load Explore.';
  }
  return result.feed!;
});

@RoutePage()
class ExploreScreenSmall extends ConsumerStatefulWidget {
  const ExploreScreenSmall({super.key});

  @override
  ConsumerState<ExploreScreenSmall> createState() => _ExploreScreenSmallState();
}

class _ExploreScreenSmallState extends ConsumerState<ExploreScreenSmall>
    with AutomaticKeepAliveClientMixin {
  bool _surpriseLoading = false;

  void loadData() {
    BookRepository.invalidateCache(url: popular);
    final previousFeed = ref.read(exploreFeedProvider).asData?.value;
    for (final link in previousFeed?.feed?.link ?? <Link>[]) {
      final url = link.href;
      if (url == null) continue;
      BookRepository.invalidateCache(url: url);
      ref.invalidate(genreFeedNotifierProvider(url));
    }

    ref.invalidate(exploreFeedProvider);
  }

  Future<void> _refreshExplore() async {
    loadData();
    try {
      await ref.read(exploreFeedProvider.future);
    } catch (error, stackTrace) {
      debugPrint('Could not refresh Explore: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh Explore: $error')),
        );
      }
    }
  }

  Future<void> _surpriseMe() async {
    if (_surpriseLoading) return;
    setState(() => _surpriseLoading = true);
    try {
      final page = Random().nextInt(12) + 1;
      final result = await ref.read(exploreRepositoryProvider).getGenreFeed(
            gutendexBooksUrl(sort: 'popular', page: page),
          );
      final entries = result.feed?.feed?.entry ?? [];
      if (entries.isEmpty) {
        throw result.failure?.description ??
            'No books are available on this catalog page.';
      }
      final entry = entries[Random().nextInt(entries.length)];
      if (!mounted) return;
      final id = entry.id?.t ?? 'book';
      context.router.push(
        BookDetailsRoute(
          entry: entry,
          imgTag: 'surprise-cover-$id',
          titleTag: 'surprise-title-$id',
          authorTag: 'surprise-author-$id',
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Surprise Me discovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find a random book: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _surpriseLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final exploreDataState = ref.watch(exploreFeedProvider);
    return Scaffold(
      appBar: context.isSmallScreen
          ? AppBar(
              centerTitle: true,
              title: const Text('Explore'),
              actions: [
                IconButton(
                  tooltip: 'Surprise me with a book',
                  onPressed: _surpriseLoading ? null : _surpriseMe,
                  icon: _surpriseLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.shuffle),
                ),
              ],
            )
          : null,
      floatingActionButton: context.isSmallScreen
          ? null
          : FloatingActionButton.extended(
              onPressed: _surpriseLoading ? null : _surpriseMe,
              icon: const Icon(Icons.shuffle),
              label: Text(_surpriseLoading ? 'Finding a book…' : 'Surprise Me'),
            ),
      body: exploreDataState.maybeWhen(
        orElse: () => const SizedBox.shrink(),
        loading: () => const LoadingWidget(),
        data: (feeds) {
          final links = feeds.feed?.link ?? [];
          final hasTopSpacer = !context.isSmallScreen;
          return RefreshIndicator(
            onRefresh: _refreshExplore,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: links.length + (hasTopSpacer ? 1 : 0),
              itemBuilder: (context, index) {
                final linkIndex = index - (hasTopSpacer ? 1 : 0);
                if (linkIndex < 0) return const SizedBox(height: 30.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: _SectionBookList(link: links[linkIndex]),
                );
              },
            ),
          );
        },
        error: (error, _) {
          return MyErrorWidget(
            message: error.toString(),
            refreshCallBack: () => loadData(),
          );
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _SectionHeader extends StatelessWidget {
  final Link link;

  const _SectionHeader({required this.link});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              '${link.title}',
              style: const TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              context.router.push(
                GenreRoute(title: '${link.title}', url: link.href!),
              );
            },
            child: Text(
              'See All',
              style: TextStyle(
                color: context.theme.colorScheme.secondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBookList extends ConsumerStatefulWidget {
  final Link link;

  const _SectionBookList({required this.link});

  @override
  ConsumerState<_SectionBookList> createState() => _SectionBookListState();
}

class _SectionBookListState extends ConsumerState<_SectionBookList>
    with AutomaticKeepAliveClientMixin {
  void _fetch() {
    ref.read(genreFeedNotifierProvider(widget.link.href!).notifier).fetch();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(link: widget.link),
        const SizedBox(height: 10.0),
        SizedBox(
          height: 200,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: ref
                .watch(genreFeedNotifierProvider(widget.link.href!))
                .maybeWhen(
                  orElse: () => const SizedBox.shrink(),
                  loading: () => const LoadingWidget(),
                  data: (data) {
                    final books = data.books;
                    if (books.isEmpty) {
                      return const Center(
                        child:
                            Text('No books are available in this shelf yet.'),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: books.length,
                      shrinkWrap: true,
                      itemBuilder: (BuildContext context, int index) {
                        final Entry entry = books[index];

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5.0,
                            vertical: 10.0,
                          ),
                          child:
                              BookCard(img: entry.link![1].href!, entry: entry),
                        );
                      },
                    );
                  },
                  error: (error, _) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 28),
                            const SizedBox(height: 8),
                            const Text(
                              'This shelf could not be refreshed.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: _fetch,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}
