import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter_ebook_app/src/common/common.dart';

typedef BookRepositoryData = ({CategoryFeed? feed, HttpFailure? failure});

bool cachedBookMatchesQuery(Entry entry, String query) {
  final terms = normalizeGutendexSearchQuery(query)
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  if (terms.isEmpty) return false;

  final searchableText = [
    entry.title?.t,
    entry.author?.name?.t,
    ...?entry.category?.map((category) => category.label),
  ].whereType<String>().join(' ').toLowerCase();
  return terms.every(searchableText.contains);
}

String? epubDownloadUrl(Entry entry) {
  for (final link in entry.link ?? <Link1>[]) {
    if (link.type == 'application/epub+zip' &&
        link.href != null &&
        link.href!.isNotEmpty) {
      return link.href;
    }
  }
  return null;
}

class _CachedBookFeed {
  final BookRepositoryData data;
  final DateTime cachedAt;

  const _CachedBookFeed(this.data, this.cachedAt);
}

abstract class BookRepository {
  static const _cacheDuration = Duration(minutes: 5);
  static const _catalogRequestTimeout = Duration(seconds: 30);
  static const _maximumCachedFeeds = 50;
  static final Map<String, _CachedBookFeed> _feedCache = {};
  static final Map<String, Future<BookRepositoryData>> _pendingRequests = {};
  static final List<Completer<void>> _requestWaiters = [];
  static int _activeRequests = 0;
  static const int _maximumConcurrentRequests = 3;

  final Dio httpClient;

  const BookRepository(this.httpClient);

  static void invalidateCache({required String url}) {
    _feedCache.remove(_cacheKey(url));
  }

  static String _cacheKey(String url) => url.replaceAll(baseURL, '');

  static List<Entry> findCachedEntries(String query) {
    final matches = <String, Entry>{};
    for (final cachedFeed in _feedCache.values) {
      for (final entry in cachedFeed.data.feed?.feed?.entry ?? <Entry>[]) {
        if (cachedBookMatchesQuery(entry, query)) {
          final id = entry.id?.t;
          if (id != null) matches.putIfAbsent(id, () => entry);
        }
      }
    }

    return matches.values.toList();
  }

  Future<BookRepositoryData> getCategory(String url) async {
    final cacheKey = _cacheKey(url);
    final cached = _feedCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheDuration) {
      // Keep the original insertion order stable; cache hits should not
      // evict useful genre feeds simply because another category was opened.
      return cached.data;
    }

    final pendingRequest = _pendingRequests[cacheKey];
    if (pendingRequest != null) {
      return pendingRequest;
    }

    final request = _fetchCategory(_requestUrl(url), sourceUrl: url);
    _pendingRequests[cacheKey] = request;
    try {
      final result = await request;
      if (result.feed == null) {
        if (cached != null) {
          // Stale-while-error: a temporary catalog outage must not blank a
          // category that was successfully loaded before.
          return cached.data;
        }
      }
      if (result.feed != null) {
        _feedCache[cacheKey] = _CachedBookFeed(result, DateTime.now());
        while (_feedCache.length > _maximumCachedFeeds) {
          _feedCache.remove(_feedCache.keys.first);
        }
      }
      return result;
    } finally {
      if (identical(_pendingRequests[cacheKey], request)) {
        _pendingRequests.remove(cacheKey);
      }
    }
  }

  Future<BookRepositoryData> _fetchCategory(
    String url, {
    required String sourceUrl,
  }) async {
    final sourceQuery = Uri.parse(sourceUrl).queryParameters;
    final isTopicRequest = sourceQuery.containsKey('topic');
    final languages = isTopicRequest
        ? sourceQuery['languages']
                ?.split(',')
                .where((language) => language.isNotEmpty)
                .toList() ??
            <String>[]
        : <String>[];
    final copyright = isTopicRequest
        ? switch (sourceQuery['copyright']) {
            'true' => true,
            'false' => false,
            _ => null,
          }
        : null;
    await _acquireRequestSlot();
    try {
      return await _fetchCategoryWithRetry(
        url,
        languages: languages,
        copyright: copyright,
        includePaginationLink: isTopicRequest,
      );
    } finally {
      _releaseRequestSlot();
    }
  }

  static String _requestUrl(String url) {
    final uri = Uri.parse(url);
    final query = uri.queryParameters;
    final topic = query['topic'];
    if (topic == null) return url;

    return uri.replace(
      queryParameters: {
        'topic': topic,
        if (query['page'] != null) 'page': query['page'],
        if (query['sort'] != null) 'sort': query['sort'],
      },
    ).toString();
  }

  static Future<void> _acquireRequestSlot() async {
    if (_activeRequests >= _maximumConcurrentRequests) {
      final waiter = Completer<void>();
      _requestWaiters.add(waiter);
      await waiter.future;
      // The released slot is transferred directly to this waiter.
      return;
    }
    _activeRequests++;
  }

  static void _releaseRequestSlot() {
    if (_requestWaiters.isNotEmpty) {
      _requestWaiters.removeAt(0).complete();
      return;
    }
    _activeRequests--;
  }

  Future<BookRepositoryData> _fetchCategoryWithRetry(
    String url, {
    required List<String> languages,
    required bool? copyright,
    required bool includePaginationLink,
  }) async {
    try {
      final res = await httpClient.get(
        url,
        options: Options(
          sendTimeout: _catalogRequestTimeout,
          receiveTimeout: _catalogRequestTimeout,
        ),
      );
      return _parseCategoryResponse(
        res.data,
        languages: languages,
        copyright: copyright,
        includePaginationLink: includePaginationLink,
      );
    } on DioException catch (error, stackTrace) {
      // Do not retry a timed-out connection: doing so multiplies a slow
      // catalog request into a 25-30 second wait for every Explore shelf.
      // Retry only explicit transient server/rate-limit responses.
      final retryable = error.response?.statusCode != null &&
          (error.response!.statusCode! >= 500 ||
              error.response!.statusCode == 429);
      if (retryable) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          final retry = await httpClient.get(
            url,
            options: Options(
              sendTimeout: _catalogRequestTimeout,
              receiveTimeout: _catalogRequestTimeout,
            ),
          );
          return _parseCategoryResponse(
            retry.data,
            languages: languages,
            copyright: copyright,
            includePaginationLink: includePaginationLink,
          );
        } on DioException catch (retryError) {
          debugPrint('Retry failed for $url: ${retryError.message}');
        }
      }
      final statusCode = error.response?.statusCode ?? 500;
      debugPrint('Gutendex request failed for $url: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (statusCode == 404) {
        return (feed: null, failure: HttpFailure.notFound);
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return (feed: null, failure: HttpFailure.timeout);
      }
      if (error.type == DioExceptionType.connectionError) {
        return (feed: null, failure: HttpFailure.connection);
      }
      if (error.type == DioExceptionType.badResponse) {
        return (feed: null, failure: HttpFailure.server);
      }
      return (feed: null, failure: HttpFailure.unknown);
    }
  }

  BookRepositoryData _parseCategoryResponse(
    Object? data, {
    required List<String> languages,
    required bool? copyright,
    required bool includePaginationLink,
  }) {
    final Object? decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) {
      throw const FormatException('Gutendex returned an invalid response.');
    }

    final results = decoded['results'];
    if (results is! List) {
      throw const FormatException('Gutendex response has no book results.');
    }

    final entries = results
        .whereType<Map>()
        .where(
          (book) => _matchesTopicFilters(
            book,
            languages: languages,
            copyright: copyright,
          ),
        )
        .map((book) => Map<String, dynamic>.from(book))
        .map(gutendexBookToEntry)
        .toList();
    final nextPageUrl = decoded['next'];
    final links = _genreLinks();
    if (includePaginationLink && nextPageUrl is String) {
      links.add(Link(rel: 'next', href: nextPageUrl));
    }

    return (
      feed: CategoryFeed(
        feed: Feed(link: links, entry: entries),
      ),
      failure: null,
    );
  }

  bool _matchesTopicFilters(
    Map book, {
    required List<String> languages,
    required bool? copyright,
  }) {
    if (languages.isNotEmpty) {
      final bookLanguages = book['languages'];
      if (bookLanguages is! List ||
          !bookLanguages.any((language) => languages.contains(language))) {
        return false;
      }
    }
    return copyright == null || book['copyright'] == copyright;
  }

  List<Link> _genreLinks() => [
        Link(title: 'Short Stories', href: shortStory),
        Link(title: 'Science Fiction', href: sciFi),
        Link(title: 'Adventure', href: actionAdventure),
        Link(title: 'Mystery', href: mystery),
        Link(title: 'Romance', href: romance),
        Link(title: 'Horror', href: horror),
        Link(title: 'History', href: history),
        Link(title: 'Poetry', href: poetry),
        Link(title: 'Children', href: children),
        Link(title: 'Drama', href: drama),
      ];
}

Entry gutendexBookToEntry(Map<String, dynamic> book) {
  final id = book['id']?.toString() ?? 'unknown';
  final title = book['title'] as String? ?? 'Untitled';
  final authors = book['authors'];
  final author = authors is List && authors.isNotEmpty && authors.first is Map
      ? Map<String, dynamic>.from(authors.first as Map)
      : <String, dynamic>{};
  final authorName = author['name'] as String? ?? 'Unknown author';
  final rawFormats = book['formats'];
  final formats = rawFormats is Map
      ? Map<String, dynamic>.from(rawFormats)
      : <String, dynamic>{};
  final epubUrl = formats['application/epub+zip'] as String?;
  final subjects = book['subjects'];
  final bookshelves = book['bookshelves'];
  final summaries = book['summaries'];
  final description = summaries is List
      ? summaries.whereType<String>().firstWhere(
            (summary) => summary.trim().isNotEmpty,
            orElse: () => '',
          )
      : '';
  final summary = description.isNotEmpty
      ? description
      : _catalogDescription(
          authorName: authorName,
          subjects: subjects,
          bookshelves: bookshelves,
        );
  final categories = <String>{
    if (bookshelves is List) ...bookshelves.whereType<String>(),
    if (subjects is List) ...subjects.whereType<String>(),
  }.take(10).map((label) => Category(label: label));
  final coverUrl = formats['image/jpeg'] as String? ??
      'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg';

  return Entry(
    id: Id(t: id),
    title: Id(t: title),
    author: Author1(
      name: Id(t: authorName),
      uri: Id(t: gutendexBooksUrl(search: authorName)),
    ),
    summary: Id(t: summary),
    category: categories.toList(),
    link: [
      Link1(rel: 'self', href: 'https://gutendex.com/books/$id/'),
      Link1(rel: 'cover', type: 'image/jpeg', href: coverUrl),
      Link1(rel: 'alternate', href: 'https://www.gutenberg.org/ebooks/$id'),
      if (epubUrl != null && epubUrl.isNotEmpty)
        Link1(rel: 'download', type: 'application/epub+zip', href: epubUrl),
    ],
  );
}

String _catalogDescription({
  required String authorName,
  required Object? subjects,
  required Object? bookshelves,
}) {
  final labels = <String>{
    if (subjects is List) ...subjects.whereType<String>(),
    if (bookshelves is List) ...bookshelves.whereType<String>(),
  }.take(5).toList();
  if (labels.isEmpty) {
    return 'A public-domain ebook by $authorName, available from Project '
        'Gutenberg.';
  }
  return 'A public-domain ebook by $authorName. Catalog subjects: '
      '${labels.join(', ')}.';
}
