import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around the [SpeechToText] singleton that ensures each screen
/// receives its own status/error callbacks.
///
/// `SpeechToText()` is a singleton factory (`SpeechToText() => _instance`) and
/// its `initialize()` short-circuits once it has already been initialized (see
/// `speech_to_text.dart`). That means a second screen calling `initialize()`
/// never gets its `onError` / `onStatus` handlers registered - the plugin keeps
/// calling whichever screen happened to initialize it first.
///
/// [SpeechService] registers the plugin-level handlers exactly once (on first
/// use) and routes every callback to the most recently attached *alive*
/// screen listener. Because screens that are pushed on top of another (or that
/// come back after a pop) also re-attach, no screen ever permanently steals -
/// or loses - the callbacks again.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final SpeechToText _speech = SpeechToText();

  /// Registered screen listeners, keyed by a monotonically increasing token so
  /// the most recently attached one (the visible screen, normally) wins.
  final Map<
      int,
      ({
        SpeechStatusListener onStatus,
        SpeechErrorListener onError,
      })> _listeners = {};
  int _nextToken = 0;
  bool _ready = false;

  /// Binds this screen's callbacks to the shared engine and makes sure it is
  /// initialized. Returns `(token, ready)` - keep the token and call
  /// [detach] with it from `dispose()`.
  Future<(int, bool)> attach({
    required SpeechStatusListener onStatus,
    required SpeechErrorListener onError,
  }) async {
    final token = ++_nextToken;
    _listeners[token] = (onStatus: onStatus, onError: onError);
    if (!_ready) {
      try {
        _ready = await _speech.initialize(
          debugLogging: true,
          onError: _dispatchError,
          onStatus: _dispatchStatus,
        );
      } catch (_) {
        _ready = false;
      }
    }
    return (token, _ready);
  }

  /// Removes a screen's callbacks when it is disposed, so a stale (popped)
  /// screen can never keep - or receive - speech events.
  void detach(int token) {
    _listeners.remove(token);
  }

  /// The most recently attached listener that is still alive.
  _ScreenListener? get _active => _listeners.isEmpty
      ? null
      : _listeners[_listeners.keys.reduce((a, b) => a > b ? a : b)];

  void _dispatchStatus(String status) => _active?.onStatus(status);
  void _dispatchError(SpeechRecognitionError error) =>
      _active?.onError(error);

  /// Starts a listening session for the currently attached screen.
  void listen({
    required SpeechResultListener onResult,
    String localeId = '',
    Duration listenFor = const Duration(seconds: 20),
  }) {
    _speech.listen(
      onResult: onResult,
      listenOptions: SpeechListenOptions(
        listenFor: listenFor,
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stop() => _speech.stop();
  void cancel() => _speech.cancel();

  bool get isListening => _speech.isListening;

  /// Clears a stuck/busy recognizer before a fresh listening session.
  ///
  /// Speech recognition on some devices gets "stuck" after a no-match error:
  /// the plugin still reports listening even though no audio is being captured.
  /// Cancelling and briefly waiting resets the internal state so the next
  /// [listen] actually starts.
  Future<void> cancelAndWait() async {
    if (_speech.isListening) {
      _speech.cancel();
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  /// Returns an installed English speech locale code (e.g. "en-US"), or
  /// "en-US" as a last resort.
  ///
  /// This must NEVER fall back to an empty string: with an empty locale the
  /// engine uses the device's default language. On phones whose default is
  /// Arabic (for example), an English word like "phone" then comes back
  /// transcribed as "فون" (the closest Arabic-language spelling).
  Future<String> resolveEnglishLocale() async {
    try {
      final locales = await _speech.locales();
      String? anyEnglish;
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id.startsWith('en')) {
          anyEnglish ??= locale.localeId;
          // Prefer a plain, engine-supported tag (en / en-US / en-GB ...)
          // over Android's five-part ids like "en-us-x-tpd".
          if (id == 'en' ||
              id == 'en-us' ||
              id == 'en-gb' ||
              id == 'en-in' ||
              id == 'en-au' ||
              id == 'en-ca') {
            return locale.localeId;
          }
        }
      }
      if (anyEnglish != null) return anyEnglish;
    } catch (_) {
      // Fall through to the hard-coded default below.
    }
    // English speech recognition is effectively always available through the
    // Google app even when it is not listed, so force it rather than letting
    // the recognition happen in the device's (possibly Arabic) default.
    return 'en-US';
  }
}

/// A bound screen's status/error callbacks.
typedef _ScreenListener =
    ({SpeechStatusListener onStatus, SpeechErrorListener onError});
