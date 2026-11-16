import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:flutter_ebook_app/src/features/library/data/epub_cache.dart';
import 'package:flutter_ebook_app/src/features/library/data/reading_shelf.dart';
import 'package:flutter_ebook_app/src/features/library/presentation/ui/screens/epub_reader_screen.dart';

class ReadBookScreen extends StatefulWidget {
  final String id;
  final String title;
  final String url;
  final String author;
  final String? localPath;
  final String? cover;

  const ReadBookScreen({
    super.key,
    required this.id,
    required this.title,
    required this.url,
    this.author = 'Unknown author',
    this.localPath,
    this.cover,
  });

  @override
  State<ReadBookScreen> createState() => _ReadBookScreenState();
}

class _ReadBookScreenState extends State<ReadBookScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
    ),
  );
  String? _error;
  bool _opening = false;
  bool _fromCache = false;
  double? _downloadProgress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  CancelToken? _cancelToken;
  File? _temporaryReadingFile;

  @override
  void initState() {
    super.initState();
    unawaited(_openBook());
  }

  Future<void> _openBook() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
      _fromCache = false;
      _downloadProgress = null;
      _receivedBytes = 0;
      _totalBytes = 0;
      _cancelToken = CancelToken();
    });

    try {
      final cached =
          widget.localPath != null || await epubCache.contains(widget.id);
      final file = widget.localPath != null
          ? await _localEpubFile(widget.localPath!)
          : cached
              ? await epubCache.fileFor(widget.id)
              : await epubCache.downloadForReading(
                  dio: _dio,
                  id: widget.id,
                  url: widget.url,
                  cancelToken: _cancelToken!,
                  onProgress: (received, total) {
                    if (!mounted) return;
                    setState(() {
                      _receivedBytes = received;
                      _totalBytes = total;
                      _downloadProgress = total > 0
                          ? (received / total).clamp(0, 1).toDouble()
                          : null;
                    });
                  },
                );
      if (!cached && widget.localPath == null) {
        _temporaryReadingFile = file;
      }

      await ReadingShelf.record(
        id: widget.id,
        title: widget.title,
        author: widget.author,
        cover: widget.cover ??
            'https://www.gutenberg.org/cache/epub/${widget.id}/pg${widget.id}.cover.medium.jpg',
        url: widget.url,
        path: widget.localPath != null ? file.path : null,
      );
      if (!mounted) return;
      _fromCache = cached;
      final deleteWhenReaderCloses = _temporaryReadingFile != null;
      _temporaryReadingFile = null;
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => EpubReaderScreen(
              bookId: widget.id,
              filePath: file.path,
              deleteFileOnClose: deleteWhenReaderCloses,
            ),
          ),
        ),
      );
    } catch (error, stackTrace) {
      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }
      debugPrint('Failed to open "${widget.title}" for reading: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_temporaryReadingFile != null &&
          await _temporaryReadingFile!.exists()) {
        await _temporaryReadingFile!.delete();
        _temporaryReadingFile = null;
      }
      if (mounted) {
        setState(() {
          _error = 'Could not open this book. Check your internet connection '
              'and try again. $error';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<File> _localEpubFile(String path) async {
    final file = File(path);
    if (!await epubCache.isValidFile(file)) {
      throw const FormatException(
        'The imported EPUB file is missing or invalid.',
      );
    }
    return file;
  }

  void _cancelDownload() {
    _cancelToken?.cancel('Reading preparation cancelled.');
    if (mounted) Navigator.maybePop(context);
  }

  @override
  void dispose() {
    _dio.close();
    final temporary = _temporaryReadingFile;
    if (temporary != null && temporary.existsSync()) {
      unawaited(temporary.delete().then<void>((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _error == null && !_fromCache;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading)
                      LinearProgressIndicator(value: _downloadProgress)
                    else
                      const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      isLoading
                          ? 'Loading book into the reader...'
                          : 'Opening your book...',
                    ),
                    if (_receivedBytes > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        _totalBytes > 0
                            ? '${_formatBytes(_receivedBytes)} of ${_formatBytes(_totalBytes)}'
                            : '${_formatBytes(_receivedBytes)} prepared',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (isLoading)
                      TextButton(
                        onPressed: _opening ? _cancelDownload : null,
                        child: const Text('Cancel'),
                      ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _opening ? null : _openBook,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
