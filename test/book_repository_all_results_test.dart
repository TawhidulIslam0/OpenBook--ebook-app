import 'package:dio/dio.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps all 32 catalog results, including books without EPUB files',
    () async {
      final books = List.generate(
        32,
        (index) => {
          'id': 1001 + index,
          'title': 'Catalog book $index',
          'authors': [],
          'formats': {
            'image/jpeg': 'https://example.test/${1001 + index}.jpg',
            if (index == 0)
              'application/epub+zip': 'https://example.test/1001.epub',
            if (index > 0) 'application/pdf': 'https://example.test/$index.pdf',
          },
        },
      );
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(requestOptions: options, data: {'results': books}),
              );
            },
          ),
        );

      final result = await _TestBookRepository(
        dio,
      ).getCategory('https://gutendex.com/books/?all-results-test=true');
      final entries = result.feed!.feed!.entry!;

      expect(entries, hasLength(32));
      expect(entries.first.title?.t, 'Catalog book 0');
      expect(entries.last.title?.t, 'Catalog book 31');
      expect(epubDownloadUrl(entries.first), 'https://example.test/1001.epub');
      expect(epubDownloadUrl(entries[1]), isNull);
    },
  );

  test('uses the responsive topic URL and applies its filters locally',
      () async {
    Uri? requestedUri;
    final books = [
      {
        'id': 1,
        'title': 'English public-domain adventure',
        'languages': ['en'],
        'copyright': false,
        'authors': [],
        'formats': {},
      },
      {
        'id': 2,
        'title': 'French adventure',
        'languages': ['fr'],
        'copyright': false,
        'authors': [],
        'formats': {},
      },
      {
        'id': 3,
        'title': 'Copyrighted English adventure',
        'languages': ['en'],
        'copyright': true,
        'authors': [],
        'formats': {},
      },
    ];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUri = options.uri;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'next': 'https://gutendex.com/books/?page=2&topic=adventure',
                  'results': books,
                },
              ),
            );
          },
        ),
      );

    final result = await _TestBookRepository(dio).getCategory(
      'https://gutendex.com/books/?languages=en&copyright=false&topic=adventure',
    );

    expect(requestedUri?.queryParameters, {'topic': 'adventure'});
    expect(result.feed?.feed?.entry?.map((entry) => entry.title?.t), [
      'English public-domain adventure',
    ]);
    expect(
      result.feed?.feed?.link?.where((link) => link.rel == 'next'),
      hasLength(1),
    );
  });
}

class _TestBookRepository extends BookRepository {
  const _TestBookRepository(super.httpClient);
}
