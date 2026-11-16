import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:iridium_reader_widget/views/viewers/epub_screen.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_ebook_app/src/features/library/data/persistent_reader_annotations.dart';
import 'package:flutter_ebook_app/src/features/library/data/reading_shelf.dart';

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({
    super.key,
    required this.bookId,
    required this.filePath,
    this.deleteFileOnClose = false,
  });

  final String bookId;
  final String filePath;
  final bool deleteFileOnClose;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  static const _settingsKey = 'openleaf.reader.settings.v1';
  final FlutterTts _textToSpeech = FlutterTts();
  Map<String, dynamic> _savedSettings = {
    'fontSize': 100,
    'theme': null,
    'landscape': false,
    'brightness': 1.0,
    'speechRate': 0.5,
  };
  String? _selectedText;
  String? _speechText;
  int _speechOffset = 0;
  int _speechBaseOffset = 0;
  bool _isSpeaking = false;
  bool _isPaused = false;
  double _readingProgress = 0;
  Future<void> _progressSaveQueue = Future<void>.value();
  String? _savedLocation;
  final Stopwatch _readingSession = Stopwatch();
  late final Future<Map<String, dynamic>> _settings = _loadSettings();

  Future<Map<String, dynamic>> _loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final recentBooks = await ReadingShelf.getRecent();
      final matchingBooks =
          recentBooks.where((book) => book['id'] == widget.bookId);
      if (matchingBooks.isNotEmpty) {
        final savedBook = matchingBooks.first;
        _readingProgress = ((savedBook['progress'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 100.0)
            .toDouble();
        _savedLocation = savedBook['position'] as String?;
      }
    } catch (error, stackTrace) {
      // A damaged reading-history record must not prevent the book itself
      // from opening. The reader will still be usable from the first page.
      debugPrint('Could not restore reading position: $error\n$stackTrace');
    }

    final raw = preferences.getString(_settingsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['fontSize'] is int) {
          _savedSettings = {
            ..._savedSettings,
            ...Map<String, dynamic>.from(decoded),
          };
        } else {
          throw const FormatException('Saved reader settings are invalid.');
        }
      } catch (error, stackTrace) {
        debugPrint('Ignoring invalid reader settings: $error\n$stackTrace');
        await preferences.remove(_settingsKey);
      }
    }

    // Device brightness/orientation plugins can fail on some emulators. They
    // are optional preferences and must never block EPUB rendering.
    try {
      await _applyReaderPreferences();
    } catch (error, stackTrace) {
      debugPrint(
          'Could not apply saved reader preferences: $error\n$stackTrace');
    }
    return Map<String, dynamic>.from(_savedSettings);
  }

  void _saveSettings(Map<String, dynamic> settings) {
    _savedSettings = {..._savedSettings, ...settings};
    unawaited(
      _persistSettings().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Could not save reading settings: $error\n$stackTrace');
      }),
    );
  }

  Future<void> _persistSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(_savedSettings));
  }

  Future<void> _applyReaderPreferences() async {
    final landscape = _savedSettings['landscape'] == true;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
    await ScreenBrightness.instance.setApplicationScreenBrightness(
      (_savedSettings['brightness'] as num).toDouble(),
    );
  }

  Future<void> _setLandscape(bool landscape) async {
    _savedSettings['landscape'] = landscape;
    await _applyReaderPreferences();
    await _persistSettings();
  }

  Future<void> _setBrightness(double brightness) async {
    _savedSettings['brightness'] = brightness;
    await ScreenBrightness.instance.setApplicationScreenBrightness(brightness);
    await _persistSettings();
  }

  Future<void> _speak(String text, {int offset = 0}) async {
    final startOffset = offset.clamp(0, text.length);
    _speechText = text;
    _speechOffset = startOffset;
    _speechBaseOffset = startOffset;
    await _textToSpeech.setSpeechRate(
      (_savedSettings['speechRate'] as num).toDouble(),
    );
    await _textToSpeech.speak(text.substring(startOffset));
    if (mounted) {
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }

  Future<void> _pauseSpeech() async {
    await _textToSpeech.pause();
    if (mounted) setState(() => _isPaused = true);
  }

  Future<void> _stopSpeech() async {
    await _textToSpeech.stop();
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    }
  }

  Future<void> _showReaderTools() async {
    var brightness = (_savedSettings['brightness'] as num).toDouble();
    var landscape = _savedSettings['landscape'] == true;
    var speechRate = (_savedSettings['speechRate'] as num).toDouble();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reader settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.brightness_6_outlined),
                    Expanded(
                      child: Slider(
                        label: '${(brightness * 100).round()}%',
                        value: brightness,
                        onChanged: (value) {
                          setDialogState(() => brightness = value);
                          unawaited(
                              _saveToolSetting(() => _setBrightness(value)));
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Landscape reading'),
                  value: landscape,
                  onChanged: (value) => setDialogState(() => landscape = value),
                ),
                Slider(
                  label: 'Speech rate ${speechRate.toStringAsFixed(1)}',
                  min: 0.2,
                  max: 0.8,
                  value: speechRate,
                  onChanged: (value) =>
                      setDialogState(() => speechRate = value),
                ),
                const Text('Text-to-speech speed'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    final orientationChanged =
        landscape != (_savedSettings['landscape'] == true);
    _savedSettings['speechRate'] = speechRate;
    if (orientationChanged) _savedSettings['landscape'] = landscape;
    await _persistSettings();
    if (orientationChanged) await _applyReaderPreferences();
  }

  Future<void> _saveToolSetting(Future<void> Function() save) async {
    try {
      await save();
    } catch (error, stackTrace) {
      debugPrint('Could not apply reader setting: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this reader setting: $error')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _readingSession.start();
    _textToSpeech.setProgressHandler(
      (String text, int start, int end, String word) {
        _speechOffset = _speechBaseOffset + start;
      },
    );
    _textToSpeech.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
          _speechOffset = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _readingSession.stop();
    unawaited(
      _progressSaveQueue
          .then(
        (_) => ReadingShelf.addReadingTime(
          id: widget.bookId,
          seconds: _readingSession.elapsed.inSeconds,
        ),
      )
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Could not save reading time: $error\n$stackTrace');
      }),
    );
    unawaited(_textToSpeech.stop());
    if (widget.deleteFileOnClose) {
      final temporaryFile = File(widget.filePath);
      unawaited(temporaryFile.exists().then((exists) async {
        if (exists) await temporaryFile.delete();
      }));
    }
    unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    unawaited(SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    ));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _settings,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Reader settings error')),
              body: Center(
                child: Text(
                  'Could not load your saved reading settings: '
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final settings = snapshot.data!;
          return Stack(
            children: [
              EpubScreen.fromPath(
                filePath: widget.filePath,
                readerAnnotationRepository:
                    PersistentReaderAnnotationRepository(widget.bookId),
                location: _savedLocation,
                paginationCallback: (pagination) {
                  final totalProgression =
                      pagination.locator.locations.totalProgression;
                  final nextProgress =
                      ((totalProgression ?? (pagination.percent / 100.0)) * 100)
                          .clamp(0.0, 100.0)
                          .toDouble();
                  if (mounted &&
                      (nextProgress - _readingProgress).abs() >= 0.5) {
                    setState(() => _readingProgress = nextProgress);
                  }
                  _queueProgressSave(
                    nextProgress,
                    pagination.locator.json,
                  );
                },
                settings: '${settings['fontSize']}',
                theme: jsonEncode(settings['theme']),
                onSettingsChanged: _saveSettings,
                onTextSelected: (text) => setState(() {
                  _selectedText = text;
                  _speechText = text;
                  _speechOffset = 0;
                }),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, left: 8),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(.92),
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(.92),
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Reader settings and appearance',
                        onPressed: _showReaderTools,
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(.94),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.menu_book_outlined, size: 17),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Reading progress',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text('${_readingProgress.round()}%'),
                              ],
                            ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: _readingProgress / 100,
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_selectedText != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 72,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.record_voice_over_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip:
                                _isPaused ? 'Resume reading' : 'Read aloud',
                            onPressed: _isSpeaking && !_isPaused
                                ? null
                                : () => unawaited(
                                      _speak(
                                        _speechText ?? _selectedText!,
                                        offset: _isPaused ? _speechOffset : 0,
                                      ),
                                    ),
                            icon: Icon(
                                _isPaused ? Icons.play_arrow : Icons.volume_up),
                          ),
                          if (_isSpeaking && !_isPaused)
                            IconButton(
                              tooltip: 'Pause reading',
                              onPressed: () => unawaited(_pauseSpeech()),
                              icon: const Icon(Icons.pause),
                            ),
                          IconButton(
                            tooltip: 'Stop reading',
                            onPressed: () => unawaited(_stopSpeech()),
                            icon: const Icon(Icons.stop),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  void _queueProgressSave(double progress, String position) {
    _progressSaveQueue = _progressSaveQueue.then((_) async {
      try {
        await ReadingShelf.updateProgress(
          id: widget.bookId,
          progress: progress.round(),
          position: position,
        );
      } catch (error, stackTrace) {
        debugPrint('Could not save reading progress: $error\n$stackTrace');
      }
    });
  }
}
