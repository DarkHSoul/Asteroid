import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:asteroid/api/youtube_api_service.dart';

Future<AudioHandler> initAudioService() async {
  print('initAudioService called');
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.asteroid.notio.asteroid.channel.audio',
      androidNotificationChannelName: 'Asteroid Music',
      androidNotificationOngoing: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final _logger = Logger('AudioHandler');
  
  final _nextSongsController = StreamController<List<MediaItem>>.broadcast();
  
  List<MediaItem> _allFetchedSimilarSongs = [];
  String? upNextContinuationToken;
  List<MediaItem> _currentUpNextList = [];

  static const int _initialSimilarSongsCount = 25;
  
  Stream<List<MediaItem>> get nextSongsStream {
    return Stream<List<MediaItem>>.multi((controller) {
      controller.add(_currentUpNextList);
      
      final subscription = _nextSongsController.stream.listen(
        (data) => controller.add(data),
        onError: (error) => controller.addError(error),
        onDone: () => controller.close(),
      );
      
      controller.onCancel = () => subscription.cancel();
    });
  }
  List<MediaItem> get latestSimilarSongs => _allFetchedSimilarSongs;
  final YouTubeApiService youtubeApiService = YouTubeApiService();
  Stream<Duration> get positionStream => player.positionStream;
  MediaItem? _sessionFirstSong;
  MediaItem? get sessionFirstSong => _sessionFirstSong;
  
  MediaItem? _firstSearchSong;
  MediaItem? get firstSearchSong => _firstSearchSong;

  bool _skipNextInProgress = false;
  bool isAddingMoreSongs = false;
  int _playlistGeneration = 0;

  MyAudioHandler() {
    print('[UP-NEXT DEBUG] MyAudioHandler initialized');
    print('[UP-NEXT DEBUG] nextSongsStream initialized: ${_nextSongsController.stream}');
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    _listenForProcessingStateChanges();
    _listenForSettingsChanges();
    
    _initializePlayer();
  }
  void _listenForSettingsChanges() {
    player.volumeStream.listen((volume) {
      _logger.info('Volume changed to: $volume');
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  void _listenForDurationChanges() {
    player.durationStream.listen((duration) {
      final index = player.currentIndex;
      final newQueue = queue.value;
      if (index == null || newQueue.isEmpty) return;
      final oldMediaItem = newQueue[index];
      final newMediaItem = oldMediaItem.copyWith(duration: duration);
      newQueue[index] = newMediaItem;
      queue.add(newQueue);
      mediaItem.add(newMediaItem);
    });
  }

  void _listenForCurrentSongIndexChanges() {
    player.currentIndexStream.listen((index) {
      final playlist = queue.value;
      if (index == null || playlist.isEmpty || index >= playlist.length) return;
      
      final currentItem = playlist[index];
      mediaItem.add(currentItem);

      // This logic will be handled differently now.

      final buffer = 5;
      if (!isAddingMoreSongs && _playlist.length > 0 && (_playlist.length - 1 - index) < buffer) {
        _logger.info('[PRELOAD] Nearing end of playlist (index: $index, length: ${_playlist.length}). Triggering load more.');
        _loadMoreSongsIntoPlayer();
      }
    });
  }

  void _listenForSequenceStateChanges() {
    player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);
    });
  }

  void _listenForProcessingStateChanges() {
    player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await skipToNext();
      }
    });
  }

  Future<void> _initializePlayer() async {
    try {
      if (_playlist.length > 0) {
        await player.setAudioSource(_playlist);
        _logger.info('Audio player initialized with non-empty playlist.');
      } else {
        _logger.info('Audio player configured (initial playlist is empty, source will be set on first item add).');
      }
    } catch (e) {
      _logger.severe('Error configuring audio player in _initializePlayer: $e');
    }
  }  @override
  Future<void> addQueueItem(MediaItem mediaItem, {bool prefetchSimilarSongs = true}) async {
    final int currentGeneration = _playlistGeneration;
    try {
      _logger.info('Adding queue item: ${mediaItem.title} - ${mediaItem.id}');
      
      String url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        _logger.info('Detected raw videoId ($url), resolving to stream URL');
        final stream = await youtubeApiService.getStreamingUrl(url);
        if (stream != null) {
          _logger.info('Resolved videoId to stream URL (${stream.length > 50 ? stream.substring(0, 50) + "..." : stream})');
          url = stream;
          mediaItem = mediaItem.copyWith(
            id: stream,
            extras: {
              ...?mediaItem.extras,
              'url': stream,
              'videoId': mediaItem.extras?['videoId'] ?? url,
            },
          );
        } else {
          _logger.warning('Failed to resolve videoId=$url to stream URL');
        }
      }
      
      if (url.isEmpty) {
        _logger.severe('Empty URL for media item: ${mediaItem.title}');
        throw Exception('Empty URL for media item');
      }
      
      _logger.info('Using URL: $url');
      _logger.info('URL length: ${url.length} characters');
      
      _logger.info('URL start: ${url.length > 100 ? url.substring(0, 100) + "..." : url}');
      
      try {
        final uri = Uri.parse(url);
        _logger.info('Parsed URI - scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');
        
        if (uri.scheme.isEmpty) {
          throw Exception('Missing scheme in URL');
        }
      } catch (e) {
        _logger.severe('Error parsing URL: $e');
        
        if (url.startsWith('//')) {
          url = 'https:$url';
          _logger.info('Fixed URL by adding https: scheme: $url');
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
          _logger.info('Fixed URL by adding https:// scheme: $url');
        } else {
          throw Exception('Invalid URL format: $url');
        }
      }
      
      _logger.info('Creating audio source with URL');
      _logger.info('Skipping custom User-Agent header for YouTube stream (web)');
      final audioSource = AudioSource.uri(
        Uri.parse(url),
        tag: mediaItem.copyWith(id: url),
      );
      _logger.info('Audio source created successfully');
      
      _logger.info('Adding to playlist');
      await _playlist.add(audioSource);
      _logger.info('Added to playlist successfully');
      
      if (_sessionFirstSong == null) {
        _sessionFirstSong = mediaItem;
      }
      
      final newQueue = queue.value..add(mediaItem);
      queue.add(newQueue);
      _logger.info('Added to queue successfully, queue size: ${newQueue.length}');
      
      if (player.audioSource == null || (_playlist.length == 1 && player.audioSource != _playlist)) {
        _logger.info('Playlist has content, (re)setting audio source in player.');
        await player.setAudioSource(_playlist);
        _logger.info('Player (re)initialized with playlist.');
      }
      print('[UP-NEXT DEBUG] addQueueItem called with prefetchSimilarSongs: $prefetchSimilarSongs');
      if (prefetchSimilarSongs) {
        try {
          final videoId = mediaItem.extras?['videoId'] as String? ??
              _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
          if (videoId != null && videoId.isNotEmpty) {
            final playlistId = mediaItem.extras?['playlistId'] as String?;
            final params = mediaItem.extras?['params'] as String?;
            final similarVideosResponse = await youtubeApiService.fetchSimilarSongs(
              videoId,
              playlistId: playlistId,
              params: params,
            );
            if (similarVideosResponse == null) {
              print('[UP-NEXT DEBUG] No similar videos found');
              return;
            }
            final similarVideos = similarVideosResponse.videos;
            upNextContinuationToken = similarVideosResponse.continuationToken;
            print('[UP-NEXT DEBUG] Found ${similarVideos.length} similar videos');
            final fetchedMediaItems = similarVideos.map((v) => youtubeApiService.youtubeVideoToMediaItem(v)).toList();
            print('[UP-NEXT DEBUG] Converted to ${fetchedMediaItems.length} media items');

            _allFetchedSimilarSongs.clear();
            _allFetchedSimilarSongs.add(mediaItem);
            print('[UP-NEXT DEBUG] Added searched song to top of Up Next: ${mediaItem.title}');

            final headVideoId = mediaItem.extras?['videoId'] as String? ?? _extractYouTubeVideoId(mediaItem.id);

            for (final similarSong in fetchedMediaItems) {
              final similarVideoId = similarSong.extras?['videoId'] as String? ??
                  _extractYouTubeVideoId(similarSong.extras?['url'] as String? ?? similarSong.id);
              
              if (similarVideoId != null && similarVideoId != headVideoId) {
                  final isDuplicate = _allFetchedSimilarSongs.any((existing) {
                    final existingVideoId = existing.extras?['videoId'] as String? ??
                        _extractYouTubeVideoId(existing.extras?['url'] as String? ?? existing.id);
                    return existingVideoId == similarVideoId;
                  });
                  if (!isDuplicate) {
                    _allFetchedSimilarSongs.add(similarSong);
                  }
              }
            }
            print('[UP-NEXT DEBUG] _allFetchedSimilarSongs populated with ${_allFetchedSimilarSongs.length} items');

            _currentUpNextList = _allFetchedSimilarSongs.take(_initialSimilarSongsCount).toList();
            _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
            print('[UP-NEXT DEBUG] Added initial batch to stream: ${_currentUpNextList.map((e) => e.title).join(", ")}');
            
            final songsToPreload = _currentUpNextList.skip(1).take(24).toList();
            if (songsToPreload.isNotEmpty) {
                 print('[UP-NEXT DEBUG] Preloading ${songsToPreload.length} songs to player: ${songsToPreload.map((e)=>e.title).join(",")}');
                _addNextSongsToPlaylist(songsToPreload, generation: currentGeneration);
            }

          } else {
            print('[UP-NEXT DEBUG] No videoId found or videoId is empty, creating minimal up-next list');
            _allFetchedSimilarSongs.clear();
            if (_firstSearchSong != null) {
                 final firstVideoId = _firstSearchSong!.extras?['videoId'] as String? ??
                     _extractYouTubeVideoId(_firstSearchSong!.extras?['url'] as String? ?? _firstSearchSong!.id);
                 final currentVideoId = mediaItem.extras?['videoId'] as String? ??
                     _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
                 if (firstVideoId != currentVideoId) _allFetchedSimilarSongs.add(_firstSearchSong!);
            }
            _allFetchedSimilarSongs.add(mediaItem);

            _currentUpNextList = List<MediaItem>.from(_allFetchedSimilarSongs);
            _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
          }
        } catch (e) {
          print('[UP-NEXT DEBUG] Error prefetching similar songs: $e');
          _logger.warning('Error prefetching similar songs: $e');
           _allFetchedSimilarSongs.clear();
            _allFetchedSimilarSongs.add(mediaItem);
            _currentUpNextList = List<MediaItem>.from(_allFetchedSimilarSongs);
            _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
        }
      } else {
        print('[UP-NEXT DEBUG] Skipping prefetch similar songs');
        _allFetchedSimilarSongs.clear();
        _allFetchedSimilarSongs.add(mediaItem);
        _currentUpNextList = List<MediaItem>.from(_allFetchedSimilarSongs);
        _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
      }
      
    } catch (e, stackTrace) {
      _logger.severe('Error adding queue item: $e');
      _logger.severe('Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    try {
      await _playlist.removeAt(index);
      final newQueue = queue.value..removeAt(index);
      queue.add(newQueue);
    } catch (e) {
      _logger.severe('Error removing queue item: $e');
    }
  }
  @override
  Future<void> play() async {
    print('[DEBUG] play() method called');
    
    try {
      print('[DEBUG] play() - Playlist length: ${_playlist.length}');
      _logger.info('Playlist length: ${_playlist.length}');
      if (_playlist.length == 0) {
        _logger.warning('Attempted to play with empty playlist');
        print('[ERROR] play() - Empty playlist!');
        return;
      }
      
      if (player.audioSource == null) {
        print('[DEBUG] play() - Player not initialized, setting audio source');
        _logger.info('Player not initialized, setting audio source');
        await player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
        print('[DEBUG] play() - Player initialized with playlist');
      }
      
      print('[DEBUG] play() - Starting playback...');
      _logger.info('Starting playback');
      await player.play();
      _logger.info('Playback started successfully');
      print('[DEBUG] play() - Playback started successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error in play method: $e');
      _logger.severe('Stack trace: $stackTrace');
      print('[ERROR] play() - Error: $e');
      print('[ERROR] play() - Stack trace: $stackTrace');
    }
  }

  @override
  Future<void> pause() async {
    player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await player.pause();
    await player.seek(position);
    await Future.delayed(const Duration(milliseconds: 300));
    await player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.length || index >= queue.value.length) {
      _logger.warning('skipToQueueItem: Invalid index $index. Player playlist length: ${_playlist.length}, Handler queue length: ${queue.value.length}');
      return;
    }

    final bool wasPlaying = player.playing;

    if (wasPlaying) {
      await player.pause();
    }

    await player.seek(Duration.zero, index: index);

    if (wasPlaying) {
      await player.play();
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_skipNextInProgress) return;
    _skipNextInProgress = true;
    try {
      _logger.info('[SKIP NEXT DEBUG] skipToNext called.');
      final int playerQueueLengthBeforeAdd = _playlist.length;

      if (player.hasNext) {
        _logger.info('[SKIP NEXT DEBUG] Player has next. Seeking to next in player.');
        await player.seekToNext();
        await player.play();
      } else {
        _logger.info('[SKIP NEXT DEBUG] Player is at the end of its current queue (_playlist length: $playerQueueLengthBeforeAdd).');
        
        MediaItem? lastPlayedPlayerItem;
        final currentPlayingIndexInPlayer = player.currentIndex;
        if (currentPlayingIndexInPlayer != null && 
            player.sequenceState != null && 
            currentPlayingIndexInPlayer < player.sequenceState!.effectiveSequence.length) {
          final lastPlayerAudioSource = player.sequenceState!.effectiveSequence[currentPlayingIndexInPlayer];
          if (lastPlayerAudioSource.tag is MediaItem) {
            lastPlayedPlayerItem = lastPlayerAudioSource.tag as MediaItem;
            _logger.info('[SKIP NEXT DEBUG] Last played item in player: ${lastPlayedPlayerItem.title}');
          }
        }

        int lastPlayedIndexInUpNext = -1;
        if (lastPlayedPlayerItem != null) {
          lastPlayedIndexInUpNext = _currentUpNextList.indexWhere((item) {
            final itemVideoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.id);
            final lastPlayedVideoId = lastPlayedPlayerItem!.extras?['videoId'] as String? ?? _extractYouTubeVideoId(lastPlayedPlayerItem.id);
            return itemVideoId == lastPlayedVideoId && itemVideoId != null;
          });
        }
        _logger.info('[SKIP NEXT DEBUG] Index of last played song in _currentUpNextList: $lastPlayedIndexInUpNext (count: ${_currentUpNextList.length})');

        List<MediaItem> songsToConsiderAdding = [];
        if (lastPlayedIndexInUpNext != -1 && lastPlayedIndexInUpNext + 1 < _currentUpNextList.length) {
          songsToConsiderAdding = _currentUpNextList.skip(lastPlayedIndexInUpNext + 1).toList();
        }

        if (songsToConsiderAdding.isNotEmpty) {
          _logger.info('[SKIP NEXT DEBUG] Found ${songsToConsiderAdding.length} songs in _currentUpNextList to potentially add to player.');
          
          List<MediaItem> actualItemsAddedToPlayer = await _addNextSongsToPlaylist(songsToConsiderAdding, generation: _playlistGeneration);

          if (actualItemsAddedToPlayer.isNotEmpty) {
            final currentHandlerQueue = List<MediaItem>.from(queue.value);
            currentHandlerQueue.addAll(actualItemsAddedToPlayer);
            queue.add(currentHandlerQueue);
            _logger.info('[SKIP NEXT DEBUG] Manually updated handler queue. Old length: ${queue.value.length - actualItemsAddedToPlayer.length}, New length: ${currentHandlerQueue.length}');

            if (playerQueueLengthBeforeAdd < _playlist.length) { 
              _logger.info('[SKIP NEXT DEBUG] Seeking to newly added song in player at index $playerQueueLengthBeforeAdd.');
              await player.seek(Duration.zero, index: playerQueueLengthBeforeAdd);
              await player.play();
            } else {
              _logger.warning('[SKIP NEXT DEBUG] _addNextSongsToPlaylist reported items processed, but _playlist.length did not increase as expected.');
            }
          } else {
            _logger.info('[SKIP NEXT DEBUG] _addNextSongsToPlaylist processed no new songs to add to player from current batch.');
            await _tryLoadingMoreAndPlaying(playerQueueLengthBeforeAdd, lastPlayedIndexInUpNext);
          }
        } else {
          _logger.info('[SKIP NEXT DEBUG] No more songs in _currentUpNextList to add to player directly. Attempting to load more.');
          await _tryLoadingMoreAndPlaying(playerQueueLengthBeforeAdd, lastPlayedIndexInUpNext);
        }
      }
    } catch (e, st) {
      _logger.severe('[SKIP NEXT DEBUG] Error in skipToNext: $e\\n$st');
    } finally {
      _skipNextInProgress = false;
    }
  }

  Future<void> _tryLoadingMoreAndPlaying(int playerQueueLengthBeforeLoad, int lastPlayedIndexInUpNextBeforeLoad) async {
    _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) Attempting to load more songs.');
    await loadMoreSimilarSongs(); 
    
    List<MediaItem> newSongsAfterLoadMore = [];
    int startIndexForNewBatch = 0;
    if (lastPlayedIndexInUpNextBeforeLoad != -1 && lastPlayedIndexInUpNextBeforeLoad + 1 < _currentUpNextList.length) {
      startIndexForNewBatch = lastPlayedIndexInUpNextBeforeLoad + 1;
    } else if (_currentUpNextList.length > playerQueueLengthBeforeLoad) {
      startIndexForNewBatch = playerQueueLengthBeforeLoad;
    } else if (_currentUpNextList.isNotEmpty && playerQueueLengthBeforeLoad == 0){
        startIndexForNewBatch = 0;
    }


    if (startIndexForNewBatch < _currentUpNextList.length) {
      newSongsAfterLoadMore = _currentUpNextList.skip(startIndexForNewBatch).toList();
    }

    if (newSongsAfterLoadMore.isNotEmpty) {
      _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) After loadMore, found ${newSongsAfterLoadMore.length} songs to add to player, starting from _currentUpNextList index $startIndexForNewBatch.');
      List<MediaItem> actualItemsAddedToPlayer = await _addNextSongsToPlaylist(newSongsAfterLoadMore, generation: _playlistGeneration);

      if (actualItemsAddedToPlayer.isNotEmpty) {
        final currentHandlerQueue = List<MediaItem>.from(queue.value);
        currentHandlerQueue.addAll(actualItemsAddedToPlayer);
        queue.add(currentHandlerQueue);
        _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) Manually updated handler queue. New length: ${currentHandlerQueue.length}');

        if (playerQueueLengthBeforeLoad < _playlist.length) {
            _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) Seeking to first of newly added batch (after loadMore) at index $playerQueueLengthBeforeLoad.');
            await player.seek(Duration.zero, index: playerQueueLengthBeforeLoad);
            await player.play();
        } else {
             _logger.warning('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) Added songs, but new index $playerQueueLengthBeforeLoad is out of bounds or no effective change in _playlist.length ${_playlist.length}.');
        }
      } else {
         _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) After loadMore, _addNextSongsToPlaylist processed no new songs.');
      }
    } else {
      _logger.info('[SKIP NEXT DEBUG] (_tryLoadingMoreAndPlaying) After loadMore, still no new songs to play. End of all available songs.');
    }
  }

  Future<List<MediaItem>> _addNextSongsToPlaylist(List<MediaItem> songs, {required int generation}) async {
    if (generation != _playlistGeneration) {
      _logger.info('[UP-NEXT DEBUG] _addNextSongsToPlaylist call with stale generation ($generation != $_playlistGeneration) cancelled.');
      return [];
    }
    if (songs.isEmpty) {
      _logger.info('[UP-NEXT DEBUG] _addNextSongsToPlaylist called with an empty list. Nothing to do.');
      return [];
    }
    _logger.info('[UP-NEXT DEBUG] Preparing to add ${songs.length} songs to player queue.');

    final List<MediaItem> processedMediaItemsForQueue = [];

    for (final item in songs) {
      if (generation != _playlistGeneration) {
        _logger.info('[UP-NEXT DEBUG] Playlist generation changed during song processing. Aborting add task.');
        break;
      }
      try {
        final videoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.id);
        if (videoId == null || videoId.isEmpty) {
          _logger.warning('[UP-NEXT DEBUG] Could not determine videoId for "${item.title}". Skipping.');
          continue;
        }

        final streamUrl = await youtubeApiService.getStreamingUrl(videoId);
        if (streamUrl == null || streamUrl.isEmpty) {
          _logger.warning('[UP-NEXT DEBUG] Failed to get stream URL for: ${item.title} (ID: $videoId). Skipping.');
          continue;
        }
        
        final MediaItem itemWithResolvedUrl = item.copyWith(
          id: streamUrl,
          extras: {
            ...item.extras ?? {},
            'url': streamUrl,
            'videoId': videoId,
          },
        );
        
        final audioSource = AudioSource.uri(
          Uri.parse(streamUrl),
          tag: itemWithResolvedUrl,
        );
        
        await _playlist.add(audioSource);
        processedMediaItemsForQueue.add(itemWithResolvedUrl);
        _logger.info('[UP-NEXT DEBUG] Added to playlist: ${itemWithResolvedUrl.title}');
        await Future.delayed(const Duration(milliseconds: 200)); // Add a small delay

      } catch (e) {
        _logger.severe('[UP-NEXT DEBUG] Error processing "${item.title}" for playlist: $e. Skipping.');
      }
    }

    // The queue is updated automatically by the `_listenForSequenceStateChanges` listener.
    // No need to manually update it here.
    return processedMediaItemsForQueue;
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) && player.currentIndex != null) {
      await player.seek(Duration.zero, index: player.currentIndex);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      player.setShuffleModeEnabled(false);
    } else {
      player.setShuffleModeEnabled(true);
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await player.dispose();
      super.customAction(name, extras);
    }
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await player.dispose();
    await _nextSongsController.close();
    super.stop();
  }
  Future<void> clearAndPlay(MediaItem mediaItem, {bool resetSimilar = true, bool isFromSearch = false}) async {
    _playlistGeneration++;
    try {
      _logger.info('clearAndPlay called for "${mediaItem.title}", isFromSearch: $isFromSearch, resetSimilar: $resetSimilar');
      
      if (isFromSearch) {
        _firstSearchSong = mediaItem;
        print('[UP-NEXT DEBUG] Set new seed song for Up Next: ${mediaItem.title}');
      }
      
      if (resetSimilar) {
        _allFetchedSimilarSongs.clear();
        _currentUpNextList.clear();
        print('[UP-NEXT DEBUG] Cleared previous Up Next list.');
      }
      
      String? url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      print('[DEBUG] clearAndPlay - Original URL: $url');
      
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        print('[DEBUG] clearAndPlay - Detected YouTube videoId, resolving streaming URL...');
        final stream = await youtubeApiService.getStreamingUrl(url);
        if (stream != null) {
          print('[DEBUG] clearAndPlay - Successfully resolved streaming URL: ${stream.length > 50 ? stream.substring(0, 50) + "..." : stream}');
          mediaItem = mediaItem.copyWith(
            id: stream,
            extras: {
              ...?mediaItem.extras,
              'url': stream,
            },
          );
          url = stream;
        } else {
          _logger.warning('Could not resolve streaming URL for videoId=$url');
          print('[ERROR] clearAndPlay - Failed to resolve streaming URL for videoId: $url');
          throw Exception('Unable to get streaming URL for this song');
        }
      }      await player.stop();
      await _playlist.clear();
      queue.add([]);
      
      print('[DEBUG] clearAndPlay - About to call addQueueItem with: ${mediaItem.title}');
      await addQueueItem(mediaItem, prefetchSimilarSongs: resetSimilar);
      
      print('[DEBUG] clearAndPlay - About to call play()');
      await play();

    } catch (e, st) {
      _logger.severe('Error in clearAndPlay: $e');
      _logger.severe(st);
    }
  }

  String? _extractYouTubeVideoId(String? url) {
    if (url == null) return null;
    
    if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
      return url;
    }
    
    try {
      final patterns = [
        RegExp(r'youtube\.com/watch\?v=([^&]+)'),
        RegExp(r'youtu\.be/([^?]+)'),
        RegExp(r'youtube\.com/embed/([^?]+)'),
        RegExp(r'music\.youtube\.com/watch\?v=([^&]+)'),
      ];
      
      for (final pattern in patterns) {
        final match = pattern.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          return match.group(1);
        }
      }
    } catch (e) {
      _logger.warning('Error extracting YouTube ID: $e');
    }
    
    return null;
  }

  Future<void> updateQueue(List<MediaItem> newQueue) async {
    try {
      final processedItems = <MediaItem>[];
      final audioSources = <AudioSource>[];
      for (final item in newQueue) {
        try {
          String? videoId = item.extras?['videoId'] as String? ?? 
              _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
          String? streamUrl;

          if (videoId != null && videoId.length == 11) {
            streamUrl = await youtubeApiService.getStreamingUrl(videoId);
            if (streamUrl == null) {
              _logger.warning('[UP-NEXT DEBUG] Failed to get stream URL for: ${item.title} (ID: $videoId). Skipping.');
              continue;
            }
          } else {
            streamUrl = item.extras?['url'] as String? ?? item.id;
            if (streamUrl.isEmpty) {
              _logger.warning('[UP-NEXT DEBUG] Empty stream URL for: ${item.title}. Skipping.');
              continue;
            }
          }
          
          final MediaItem itemWithResolvedUrl = item.copyWith(
            id: streamUrl,
            extras: {
              ...?item.extras,
              'url': streamUrl,
              'videoId': videoId,
            },
          );
          
          final audioSource = AudioSource.uri(
            Uri.parse(streamUrl),
            tag: itemWithResolvedUrl,
          );
          
          audioSources.add(audioSource);
          processedItems.add(itemWithResolvedUrl);
          _logger.info('[UP-NEXT DEBUG] Prepared for playlist: ${itemWithResolvedUrl.title}');

        } catch (e) {
          _logger.severe('[UP-NEXT DEBUG] Error processing ${item.title}" for playlist: $e. Skipping.');
          continue;
        }
      }

      await _playlist.clear();
      if (audioSources.isNotEmpty) {
        await _playlist.addAll(audioSources);
        _logger.info('[UP-NEXT DEBUG] Added ${audioSources.length} new audio sources to just_audio playlist.');
      }
      
      queue.add(processedItems);
      
      if (player.playing) {
        final currentVideoId = _extractYouTubeVideoId(queue.value.first.id);
        final newIndex = processedItems.indexWhere((item) {
          final videoId = _extractYouTubeVideoId(item.id);
          return videoId != null && videoId == currentVideoId;
        });
        
        if (newIndex != -1) {
          _logger.info('Seeking to updated item in playlist at index $newIndex');
          await player.seek(Duration.zero, index: newIndex);
        } else {
          _logger.warning('Current item not found in updated queue, may need to restart playback');
        }
      }
    } catch (e, stackTrace) {
      _logger.severe('Error updating queue: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
  }

  Future<void> _loadMoreSongsIntoPlayer() async {
    if (isAddingMoreSongs) return;
    isAddingMoreSongs = true;
    final int currentGeneration = _playlistGeneration;

    try {
      await loadMoreSimilarSongs();
    } catch (e, st) {
      _logger.severe('Error in _loadMoreSongsIntoPlayer: $e', st);
    } finally {
      isAddingMoreSongs = false;
    }
  }

  Future<void> loadMoreSimilarSongs() async {
    if (upNextContinuationToken == null) {
      _logger.info('loadMoreSimilarSongs: No continuation token, cannot load more.');
      return;
    }
    _logger.info('loadMoreSimilarSongs: Loading more with token $upNextContinuationToken');

    final response = await youtubeApiService.fetchNextContinuation(upNextContinuationToken!);
    
    if (response != null && response.videos.isNotEmpty) {
      upNextContinuationToken = response.continuationToken;
      final fetchedMediaItems = response.videos.map((v) => youtubeApiService.youtubeVideoToMediaItem(v)).toList();
      
      final newItems = fetchedMediaItems.where((newItem) {
        final newItemId = newItem.extras?['videoId'] as String? ?? _extractYouTubeVideoId(newItem.id);
        return !_allFetchedSimilarSongs.any((existingItem) {
          final existingId = existingItem.extras?['videoId'] as String? ?? _extractYouTubeVideoId(existingItem.id);
          return existingId == newItemId;
        });
      }).toList();

      if (newItems.isNotEmpty) {
        _allFetchedSimilarSongs.addAll(newItems);
        _currentUpNextList = List.from(_allFetchedSimilarSongs); // Update the whole list
        _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
        await _addNextSongsToPlaylist(newItems, generation: _playlistGeneration);
      }
    } else {
      _logger.info('loadMoreSimilarSongs: No more songs or error fetching.');
      upNextContinuationToken = null;
    }
  }

  Future<void> removeFromUpNext(String id) async {
    _logger.info('removeFromUpNext called for id: $id');
  }

  void reorderUpNext(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final MediaItem item = _currentUpNextList.removeAt(oldIndex);
    _currentUpNextList.insert(newIndex, item);
    _nextSongsController.add(List<MediaItem>.from(_currentUpNextList));
  }

  Future<void> playFromUpNext(int index) async {
    final int currentPlayingIndex = player.currentIndex ?? -1;
    if (currentPlayingIndex != -1 && index == currentPlayingIndex) {
      // If tapping the currently playing song, do nothing or maybe seek to 0.
      await player.seek(Duration.zero);
      return;
    }

    // This logic assumes _allFetchedSimilarSongs is the source of truth for the UI
    // and _playlist is what the player knows about.
    if (index < 0 || index >= _allFetchedSimilarSongs.length) {
      _logger.warning('playFromUpNext: Invalid index $index.');
      return;
    }

    // Check if the selected song is already in the player's queue
    final selectedSong = _allFetchedSimilarSongs[index];
    final selectedVideoId = selectedSong.extras?['videoId'] as String? ?? _extractYouTubeVideoId(selectedSong.id);

    int indexInPlayerQueue = -1;
    for (int i = 0; i < _playlist.sequence.length; i++) {
      final itemInPlayer = _playlist.sequence[i].tag as MediaItem;
      final playerItemId = itemInPlayer.extras?['videoId'] as String? ?? _extractYouTubeVideoId(itemInPlayer.id);
      if (playerItemId == selectedVideoId) {
        indexInPlayerQueue = i;
        break;
      }
    }

    if (indexInPlayerQueue != -1) {
      // Song is already in the player queue, just skip to it.
      await skipToQueueItem(indexInPlayerQueue);
    } else {
      // Song is not in the player queue. We need to add it and any intermediate songs.
      _logger.info('playFromUpNext: Song not in player queue. Adding it. Index: $index');

      final int originalPlayerQueueLength = _playlist.length;

      // Find the last song in the player's queue to determine where to start adding from.
      final lastPlayerItem = _playlist.sequence.isEmpty ? null : _playlist.sequence.last.tag as MediaItem;
      int lastPlayerItemIndexInUpNext = -1;
      if (lastPlayerItem != null) {
        final lastPlayerVideoId = lastPlayerItem.extras?['videoId'] as String? ?? _extractYouTubeVideoId(lastPlayerItem.id);
        lastPlayerItemIndexInUpNext = _allFetchedSimilarSongs.indexWhere((item) {
          final itemVideoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.id);
          return itemVideoId == lastPlayerVideoId;
        });
      }

      // Determine the range of songs to add from the main up-next list.
      final int startIndex = lastPlayerItemIndexInUpNext + 1;
      final int endIndex = index;

      if (startIndex <= endIndex && endIndex < _allFetchedSimilarSongs.length) {
        final songsToAdd = _allFetchedSimilarSongs.sublist(startIndex, endIndex + 1);
        
        final List<MediaItem> addedItems = await _addNextSongsToPlaylist(songsToAdd, generation: _playlistGeneration);

        // Find the index of the *selected* song in the list of *successfully added* items.
        final selectedVideoId = _allFetchedSimilarSongs[endIndex].extras?['videoId'] as String? ?? _extractYouTubeVideoId(_allFetchedSimilarSongs[endIndex].id);
        final indexInAddedItems = addedItems.indexWhere((item) {
            final itemVideoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.id);
            return itemVideoId == selectedVideoId;
        });

        if (indexInAddedItems != -1) {
          final newIndexInPlayerQueue = originalPlayerQueueLength + indexInAddedItems;
          if (newIndexInPlayerQueue < _playlist.length) {
            await skipToQueueItem(newIndexInPlayerQueue);
          } else {
            _logger.warning('playFromUpNext: Calculated new index $newIndexInPlayerQueue is out of bounds for playlist length ${_playlist.length}.');
          }
        } else {
            _logger.warning('playFromUpNext: The selected song could not be added to the playlist. It might have failed to resolve.');
        }
      } else {
        _logger.warning('playFromUpNext: Invalid range to add songs. startIndex: $startIndex, endIndex: $endIndex, list length: ${_allFetchedSimilarSongs.length}');
      }
    }
  }

  Future<void> playMediaItem(MediaItem mediaItem, {bool isFromSearch = false}) async {
    _logger.info('playMediaItem called for: ${mediaItem.title}, isFromSearch: $isFromSearch');
    await clearAndPlay(mediaItem, resetSimilar: isFromSearch, isFromSearch: isFromSearch);
  }
}
