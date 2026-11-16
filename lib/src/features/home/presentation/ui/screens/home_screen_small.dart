import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_ebook_app/src/features/features.dart';
import 'package:flutter_ebook_app/src/features/library/presentation/ui/screens/library_screen.dart';
import 'package:flutter_ebook_app/src/features/search/presentation/ui/screens/search_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeScreenSmall extends ConsumerStatefulWidget {
  const HomeScreenSmall({super.key});

  @override
  ConsumerState<HomeScreenSmall> createState() => _HomeScreenSmallState();
}

class _HomeScreenSmallState extends ConsumerState<HomeScreenSmall> {
  void loadData() {
    ref.read(homeFeedNotifierProvider.notifier).fetch();
  }

  @override
  Widget build(BuildContext context) {
    final homeDataState = ref.watch(homeFeedNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          appName,
          style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Search books',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My Library',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: homeDataState.maybeWhen(
          orElse: () => const SizedBox.shrink(),
          loading: () => const LoadingWidget(),
          data: (feeds) {
            final popularFeed = feeds.popularFeed;
            final recentFeed = feeds.recentFeed;
            return RefreshIndicator(
              onRefresh: () async => loadData(),
              child: ListView(
                children: <Widget>[
                  if (!context.isSmallScreen) const SizedBox(height: 30.0),
                  FeaturedSection(popular: popularFeed),
                  const SizedBox(height: 20.0),
                  const _SectionTitle(title: 'Categories'),
                  const SizedBox(height: 10.0),
                  _GenreSection(popular: popularFeed),
                  const SizedBox(height: 20.0),
                  const _SectionTitle(title: 'Recently Added'),
                  const SizedBox(height: 20.0),
                  _RecentSection(
                    recent: recentFeed,
                    loading: feeds.recentLoading,
                    error: feeds.recentError,
                    onRetry: loadData,
                  ),
                ],
              ),
            );
          },
          error: (_, __) {
            return MyErrorWidget(
              refreshCallBack: () => loadData(),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturedSection extends StatelessWidget {
  final CategoryFeed popular;

  const FeaturedSection({super.key, required this.popular});

  @override
  Widget build(BuildContext context) {
    final entries = popular.feed?.entry ?? [];
    if (entries.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 15.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 5.0),
          child: BookListItem(entry: entries[index]),
        );
      },
    );
  }
}

class _GenreSection extends StatelessWidget {
  final CategoryFeed popular;

  const _GenreSection({required this.popular});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50.0,
      child: Center(
        child: ListView.builder(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          scrollDirection: Axis.horizontal,
          itemCount: popular.feed?.link?.length ?? 0,
          shrinkWrap: true,
          itemBuilder: (BuildContext context, int index) {
            final Link link = popular.feed!.link![index];

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 5.0,
                vertical: 10.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.secondary,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(20.0),
                  ),
                ),
                child: InkWell(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(20.0),
                  ),
                  onTap: () {
                    final route = GenreRoute(
                      title: '${link.title}',
                      url: link.href!,
                    );
                    if (context.isLargeScreen) {
                      context.router.replace(route);
                    } else {
                      context.router.push(route);
                    }
                  },
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Text(
                        '${link.title}',
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  final CategoryFeed recent;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _RecentSection({
    required this.recent,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final entries = recent.feed?.entry ?? [];
    if (loading) {
      return const SizedBox(height: 120, child: LoadingWidget());
    }
    if (error != null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Recently added books could not be loaded.'),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No recently added books are available.')),
      );
    }

    return ListView.builder(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 15.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        final Entry entry = entries[index];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 5.0),
          child: BookListItem(entry: entry),
        );
      },
    );
  }
}
