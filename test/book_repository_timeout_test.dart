import 'package:dio/dio.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows up to 30 seconds for a catalog response', () async {
    Duration? receiveTimeout;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            receiveTimeout = options.receiveTimeout;
            handler.resolve(
              Response(requestOptions: options, data: {'results': []}),
            );
          },
        ),
      );

    await _TestBookRepository(
      dio,
    ).getCategory('https://gutendex.com/books/?test=timeout');

    expect(receiveTimeout, const Duration(seconds: 30));
  });

  test(
    'does not replace a failed genre response with cached matches',
    () async {
      var requestCount = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestCount++;
              final topic = options.uri.queryParameters['topic'];
              if (topic != null) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
                return;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'results': [
                      {
                        'id': 1,
                        'title': 'Book about adventure',
                        'subjects': ['adventure'],
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );
      final repository = _TestBookRepository(dio);

      final popularFeed = await repository.getCategory(
        'https://gutendex.com/books/?cache-test',
      );
      final genreFeed = await repository.getCategory(
        'https://gutendex.com/books/?topic=adventure&cache-test',
      );

      expect(popularFeed.feed?.feed?.entry, hasLength(1));
      expect(genreFeed.feed, isNull);
      expect(genreFeed.failure, HttpFailure.connection);
      expect(requestCount, 2);
    },
  );
}

class _TestBookRepository extends BookRepository {
  const _TestBookRepository(super.httpClient);
}
