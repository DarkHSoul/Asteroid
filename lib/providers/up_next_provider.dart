import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/audio_handler.dart';

final _logger = Logger('UpNextProvider');

class UpNextNotifier extends ChangeNotifier {
  final MyAudioHandler _audioHandler;
  late StreamSubscription<List<MediaItem>> _upNextSubscription;

  UpNextNotifier(this._audioHandler) {
    _upNextSubscription = _audioHandler.nextSongsStream.listen((upNextList) {
      _videos = upNextList;
      notifyListeners();
    }, onError: (error) {
      _logger.severe('Error in UpNext stream: $error');
      _errorMessage = error.toString();
      notifyListeners();
    });
  }

  List<MediaItem> _videos = [];
  List<MediaItem> get videos => List.unmodifiable(_videos);

  bool get isLoading => false; 
  bool get isLoadingMore => _audioHandler.isAddingMoreSongs;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? get currentVideoId => _audioHandler.mediaItem.value?.id;

  bool get canLoadMore => _audioHandler.upNextContinuationToken != null;

  Future<void> loadMoreUpNextItems() async {
    if (isLoadingMore || !canLoadMore) return;
    
    _logger.info('UI triggered loadMoreUpNextItems');
    await _audioHandler.loadMoreSimilarSongs();
  }

  @override
  void dispose() {
    _upNextSubscription.cancel();
    super.dispose();
  }
}
