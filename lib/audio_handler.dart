import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:asteroid/api/youtube_dl_service.dart';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/api/youtube_service.dart';

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
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final _logger = Logger('AudioHandler');
  
  // Keep track of whether we're currently processing a play request
  bool _processingPlayRequest = false;  final _nextSongsController = StreamController<List<MediaItem>>.broadcast();
  List<MediaItem> _latestSimilarSongs = [];
  List<MediaItem> _currentUpNextList = [];
  
  Stream<List<MediaItem>> get nextSongsStream {
    // Create a stream that immediately emits the current value to new listeners
    return Stream<List<MediaItem>>.multi((controller) {
      // Immediately emit current value
      controller.add(_currentUpNextList);
      
      // Listen to future updates
      final subscription = _nextSongsController.stream.listen(
        (data) => controller.add(data),
        onError: (error) => controller.addError(error),
        onDone: () => controller.close(),
      );
      
      controller.onCancel = () => subscription.cancel();
    });
  }
  List<MediaItem> get latestSimilarSongs => _latestSimilarSongs;
  final YouTubeService _youtubeService = YouTubeService();
  // Add a position stream for real-time updates
  Stream<Duration> get positionStream => _player.positionStream;
  MediaItem? _sessionFirstSong; // first track started this session
  MediaItem? get sessionFirstSong => _sessionFirstSong;
  
  // Track the first song played from search for up-next list
  MediaItem? _firstSearchSong;
  MediaItem? get firstSearchSong => _firstSearchSong;

  bool _skipNextInProgress = false;
  MyAudioHandler() {
    print('[UP-NEXT DEBUG] MyAudioHandler initialized');
    print('[UP-NEXT DEBUG] nextSongsStream initialized: ${_nextSongsController.stream}');
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    _listenForProcessingStateChanges();
    _listenForSettingsChanges();
    
    // Initialize the player with the playlist
    _initializePlayer();
  }
  void _listenForSettingsChanges() {
    // Listen for volume changes from the player
    _player.volumeStream.listen((volume) {
      _logger.info('Volume changed to: $volume');
    });
  }

  Future<void> _applySettings() async {
    try {
      // Apply basic volume setting
      await _player.setVolume(1.0);
      
      _logger.info('Applied audio settings successfully');
    } catch (e) {
      _logger.severe('Error applying audio settings: $e');
    }
  }

  // Connect player events to audio handler events
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
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
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  // Listen to duration changes and update MediaItem
  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      final newQueue = queue.value;
      if (index == null || newQueue.isEmpty) return;
      final oldMediaItem = newQueue[index];
      final newMediaItem = oldMediaItem.copyWith(duration: duration);
      newQueue[index] = newMediaItem;
      queue.add(newQueue);
      mediaItem.add(newMediaItem);
    });
  }

  // Listen to current song index changes
  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      final playlist = queue.value;
      if (index == null || playlist.isEmpty) return;
      // Merely update the currently playing MediaItem – do NOT change the Up Next list.
      mediaItem.add(playlist[index]);
    });
  }

  // Listen to sequence state changes
  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);
    });
  }

  // Automatically skip to the next track when the current one finishes
  void _listenForProcessingStateChanges() {
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await skipToNext();
      }
    });
  }

  // Initialize the player with the playlist
  Future<void> _initializePlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      _logger.info('Audio player initialized with playlist');
    } catch (e) {
      _logger.severe('Error initializing audio player: $e');
    }
  }  @override
  Future<void> addQueueItem(MediaItem mediaItem, {bool prefetchSimilarSongs = true}) async {
    try {
      _logger.info('Adding queue item: ${mediaItem.title} - ${mediaItem.id}');
      
      // Get the URL from either id or extras
      String url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      
      // If the "url" looks like a bare YouTube videoId, resolve it to a stream URL first
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        _logger.info('Detected raw videoId ($url), resolving to stream URL');
        final stream = await _youtubeService.getStreamingUrl(url);
        if (stream != null) {
          _logger.info('Resolved videoId to stream URL (${stream.substring(0, 50)}...)');
          url = stream;
          // Replace mediaItem so the queue stores the playable URL
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
        throw PlaybackException('Empty URL for media item');
      }
      
      _logger.info('Using URL: $url');
      _logger.info('URL length: ${url.length} characters');
      
      // Log the start of the URL to help diagnose issues
      if (url.length > 100) {
        _logger.info('URL start: ${url.substring(0, 100)}...');
      } else {
        _logger.info('URL: $url');
      }
      
      try {
        // Validate URL format
        final uri = Uri.parse(url);
        _logger.info('Parsed URI - scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');
        
        // Ensure URL has a valid scheme
        if (uri.scheme.isEmpty) {
          throw PlaybackException('Missing scheme in URL');
        }
      } catch (e) {
        _logger.severe('Error parsing URL: $e');
        
        // Try to fix common URL issues
        if (url.startsWith('//')) {
          url = 'https:$url';
          _logger.info('Fixed URL by adding https: scheme: $url');
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
          _logger.info('Fixed URL by adding https:// scheme: $url');
        } else {
          throw PlaybackException('Invalid URL format: $url');
        }
      }
      
      // Create audio source with proper URL
      _logger.info('Creating audio source with URL');
      final audioSource = AudioSource.uri(
        Uri.parse(url),
        tag: mediaItem.copyWith(id: url), // Use URL as ID for internal player consistency
      );
      _logger.info('Audio source created successfully');
      
      // Add to playlist
      _logger.info('Adding to playlist');
      await _playlist.add(audioSource);
      _logger.info('Added to playlist successfully');
      
      // If first item, remember as session first song
      if (_sessionFirstSong == null) {
        _sessionFirstSong = mediaItem;
      }
      
      // Add to queue
      final newQueue = queue.value..add(mediaItem);
      queue.add(newQueue);
      _logger.info('Added to queue successfully, queue size: ${newQueue.length}');
      
      // If this is the first item, initialize the player
      if (_playlist.length == 1) {
        _logger.info('First item added, initializing player with playlist');
        await _player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
      }
        // Prefetch similar songs immediately so Up Next is ready
      print('[UP-NEXT DEBUG] addQueueItem called with prefetchSimilarSongs: $prefetchSimilarSongs');      if (prefetchSimilarSongs) {
        try {
          final videoId = mediaItem.extras?['videoId'] as String? ??
              _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);          if (videoId != null && videoId.isNotEmpty) {
            final playlistId = mediaItem.extras?['playlistId'] as String?;
            final params = mediaItem.extras?['params'] as String?;
            final similarVideos = await YouTubeMusicApi.fetchSimilarSongs(
              videoId,
              playlistId: playlistId,
              params: params,
            );
            print('[UP-NEXT DEBUG] Found ${similarVideos.length} similar videos');
            final nextMediaItems = similarVideos.map((v) => _youtubeService.youtubeVideoToMediaItem(v)).toList();
            print('[UP-NEXT DEBUG] Converted to ${nextMediaItems.length} media items');            if (nextMediaItems.isNotEmpty) {
              // Create the up-next list with first search song at top, followed by similar songs
              final List<MediaItem> fullUpNextList = [];
              
              // Always add the first search song at the top if it exists and is different from current song
              if (_firstSearchSong != null) {
                final firstVideoId = _firstSearchSong!.extras?['videoId'] as String? ??
                    _extractYouTubeVideoId(_firstSearchSong!.extras?['url'] as String? ?? _firstSearchSong!.id);
                final currentVideoId = mediaItem.extras?['videoId'] as String? ??
                    _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
                    
                if (firstVideoId != currentVideoId) {
                  fullUpNextList.add(_firstSearchSong!);
                  print('[UP-NEXT DEBUG] Added first search song: ${_firstSearchSong!.title}');
                }
              }
              
              // Add current song if it's not already added above
              if (fullUpNextList.isEmpty || fullUpNextList.first.id != mediaItem.id) {
                fullUpNextList.add(mediaItem);
                print('[UP-NEXT DEBUG] Added current song: ${mediaItem.title}');
              }
              
              // Add similar songs, filtering out any that might duplicate the first search song
              for (final similarSong in nextMediaItems) {
                final similarVideoId = similarSong.extras?['videoId'] as String? ??
                    _extractYouTubeVideoId(similarSong.extras?['url'] as String? ?? similarSong.id);
                    
                // Check if this similar song is already in the list
                final isDuplicate = fullUpNextList.any((existing) {
                  final existingVideoId = existing.extras?['videoId'] as String? ??
                      _extractYouTubeVideoId(existing.extras?['url'] as String? ?? existing.id);
                  return existingVideoId == similarVideoId;
                });
                
                if (!isDuplicate) {
                  fullUpNextList.add(similarSong);
                }
              }              print('[UP-NEXT DEBUG] Created fullUpNextList with ${fullUpNextList.length} items');
              _latestSimilarSongs = fullUpNextList.skip(5).toList(); // Keep most songs for the existing system
              _currentUpNextList = fullUpNextList;
              _nextSongsController.add(fullUpNextList);
              print('[UP-NEXT DEBUG] Added to stream: ${fullUpNextList.map((e) => e.title).join(", ")}');
              print('[UP-NEXT DEBUG] Kept ${_latestSimilarSongs.length} songs in _latestSimilarSongs for later loading');
                // Add the next 3-5 songs to the main playlist for seamless playback (in background)
              _addNextSongsToPlaylist(fullUpNextList.skip(1).take(4).toList());
            } else {
               // If no similar songs are found, create up-next list with first search song (if different) and current song
               final List<MediaItem> fullUpNextList = [];
               
               if (_firstSearchSong != null) {
                 final firstVideoId = _firstSearchSong!.extras?['videoId'] as String? ??
                     _extractYouTubeVideoId(_firstSearchSong!.extras?['url'] as String? ?? _firstSearchSong!.id);
                 final currentVideoId = mediaItem.extras?['videoId'] as String? ??
                     _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
                     
                 if (firstVideoId != currentVideoId) {
                   fullUpNextList.add(_firstSearchSong!);
                   print('[UP-NEXT DEBUG] Added first search song (no similar): ${_firstSearchSong!.title}');
                 }
               }
                 fullUpNextList.add(mediaItem);
               print('[UP-NEXT DEBUG] No similar songs found, list: ${fullUpNextList.map((e) => e.title).join(", ")}');
               _latestSimilarSongs = fullUpNextList;
               _currentUpNextList = fullUpNextList;
               _nextSongsController.add(fullUpNextList);}
            // Cache fetch result to avoid duplicate network calls when the track starts playing
          } else {
            print('[UP-NEXT DEBUG] No videoId found or videoId is empty');
          }
        } catch (e) {
          print('[UP-NEXT DEBUG] Error prefetching similar songs: $e');
          _logger.warning('Error prefetching similar songs: $e');
        }
      } else {
        print('[UP-NEXT DEBUG] Skipping prefetch similar songs');
      }
      
    } catch (e, stackTrace) {
      _logger.severe('Error adding queue item: $e');
      _logger.severe('Stack trace: $stackTrace');
      rethrow; // Rethrow to make sure the error is properly handled by the caller
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
    if (_processingPlayRequest) {
      _logger.info('Already processing a play request, ignoring additional request');
      return;
    }
    
    _processingPlayRequest = true;
    
    try {
      // Check if we have any items in the playlist
      print('[DEBUG] play() - Playlist length: ${_playlist.length}');
      _logger.info('Playlist length: ${_playlist.length}');
      if (_playlist.length == 0) {
        _logger.warning('Attempted to play with empty playlist');
        print('[ERROR] play() - Empty playlist!');
        return;
      }
      
      // Check if player has been properly initialized
      if (_player.audioSource == null) {
        print('[DEBUG] play() - Player not initialized, setting audio source');
        _logger.info('Player not initialized, setting audio source');
        await _player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
        print('[DEBUG] play() - Player initialized with playlist');
      }
      
      // Now play
      print('[DEBUG] play() - Starting playback...');
      _logger.info('Starting playback');
      await _player.play();
      _logger.info('Playback started successfully');
      print('[DEBUG] play() - Playback started successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error in play method: $e');
      _logger.severe('Stack trace: $stackTrace');
      print('[ERROR] play() - Error: $e');
      print('[ERROR] play() - Stack trace: $stackTrace');
    } finally {
      _processingPlayRequest = false;
    }
  }

  @override
  Future<void> pause() async {
    _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.pause();
    await _player.seek(position);
    await Future.delayed(const Duration(milliseconds: 300));
    await _player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.children.length) return;
    _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToNext() async {
    if (_skipNextInProgress) return;
    _skipNextInProgress = true;
    try {
      final playlist = queue.value;
      if (playlist.isEmpty) return;

      if (_player.hasNext) {
        // Fast-path: play the next track already in the just_audio playlist
        await _player.seekToNext();
        // Calling play after seekToNext seems to be the pattern used elsewhere.
        await _player.play();
      } else if (_latestSimilarSongs.isNotEmpty) {
        // Main playlist exhausted, add all similar songs to the main playlist
        _logger.info('[NEXT API] Main playlist exhausted, adding all similar songs (${_latestSimilarSongs.length}) to main playlist.');

        final songsToAdd = _latestSimilarSongs.toList(); // Create a copy
        final firstAddedIndex = _playlist.length; // Index where new songs will start        _latestSimilarSongs = []; // Clear the similar list as it's being moved to the main queue
        _currentUpNextList = [];
        _nextSongsController.add([]); // Update the 'Up Next' stream to show it's empty

        final audioSourcesToAdd = <AudioSource>[];
        final processedItems = <MediaItem>[];
        final youtubeDlService = YoutubeDLService();

        for (final item in songsToAdd) {
            String? videoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
            String? streamUrl;

            if (videoId != null) {
                 try {
                    // Get streaming URL for each similar song
                    streamUrl = await youtubeDlService.getStreamUrl(videoId);
                    if (streamUrl != null) {
                        _logger.info('Got streaming URL using YT-DLP service for video: $videoId');
                    }
                } catch (e) {
                    _logger.warning('Error using YT-DLP service for $videoId: $e');
                    // If fetching fails, skip this song.
                    continue;
                }            } else {
               // If it's not a YouTube video ID, assume the URL is already playable
               streamUrl = item.extras?['url'] as String? ?? item.id;
               if (streamUrl.isEmpty) {
                   _logger.warning('Skipping item with no videoId or URL: ${item.title}');
                   continue;
               }
               _logger.info('Using existing URL for non-YouTube item: ${item.title}');
            }


            if (streamUrl != null) {
                 final newItem = item.copyWith(
                    id: streamUrl, // Use streamUrl as the ID for playback
                    extras: {
                        ...?item.extras,
                        'url': streamUrl,
                        'videoId': videoId, // Keep the videoId if it exists
                    },
                );
                processedItems.add(newItem);
                audioSourcesToAdd.add(AudioSource.uri(Uri.parse(streamUrl), tag: newItem));
            }
        }

        if (audioSourcesToAdd.isNotEmpty) {
            await _playlist.addAll(audioSourcesToAdd); // Add to just_audio playlist

            // Update the main queue stream with the newly added items
            final newQueue = List<MediaItem>.from(queue.value)..addAll(processedItems);
            queue.add(newQueue);

            // Seek to the first newly added song and play
            await _player.seek(Duration.zero, index: firstAddedIndex);
            await _player.play();



        } else {
            _logger.info('[NEXT API] No valid songs found in similar list to add to main playlist.');
             await _player.stop(); // If no valid songs to add, just stop
        }

      } else {
        // No more items in main playlist or similar songs, just stop playback
        _logger.info('[NEXT API] No more songs in main playlist or similar list, stopping.');
        await _player.stop();
      }
    } finally {
      _skipNextInProgress = false;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      _player.setShuffleModeEnabled(false);
    } else {
      _player.setShuffleModeEnabled(true);
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
      super.customAction(name, extras);
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _player.dispose();
    await _nextSongsController.close();
    super.stop();
  }
  Future<void> clearAndPlay(MediaItem mediaItem, {bool resetSimilar = true, bool isFromSearch = false}) async {
    try {
      _logger.info('clearAndPlay called');
      
      // If this is from search, mark it as the first search song
      if (isFromSearch && _firstSearchSong == null) {
        _firstSearchSong = mediaItem;
        print('[UP-NEXT DEBUG] Set first search song in clearAndPlay: ${mediaItem.title}');
      }
        if (resetSimilar) {
        // Reset cached similar-songs information so a brand-new Up Next list is fetched for this track
        _latestSimilarSongs = [];
        _currentUpNextList = [];
      }      // Ensure we have a playable URL
      String? url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      print('[DEBUG] clearAndPlay - Original URL: $url');
      
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        // looks like a YouTube videoId, resolve to stream url first
        print('[DEBUG] clearAndPlay - Detected YouTube videoId, resolving streaming URL...');
        final stream = await _youtubeService.getStreamingUrl(url);
        if (stream != null) {
          print('[DEBUG] clearAndPlay - Successfully resolved streaming URL: ${stream.substring(0, 50)}...');
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
          throw PlaybackException('Unable to get streaming URL for this song');
        }
      }      await _player.stop();
      await _playlist.clear();
      queue.add([]);
      
      print('[DEBUG] clearAndPlay - About to call addQueueItem with: ${mediaItem.title}');
      // Reset player source – prefetch similar songs only when we reset the list.
      await addQueueItem(mediaItem, prefetchSimilarSongs: resetSimilar);
      
      print('[DEBUG] clearAndPlay - About to call play()');
      await play();
      // Log benzer şarkılar
      // _logger.info('[NEXT API] (clearAndPlay) Latest similar songs: ' + _latestSimilarSongs.length.toString());
      for (final _ in _latestSimilarSongs) {
        // _logger.info('[NEXT API] (clearAndPlay)   - ' + item.title + ' (' + item.id + ')');
      }

      // (If we cleared at the beginning, do NOT clear again here.)
    } catch (e, st) {
      _logger.severe('Error in clearAndPlay: $e');
      _logger.severe(st);
    }
  }

  // Extract YouTube video ID from various URL formats
  String? _extractYouTubeVideoId(String? url) {
    if (url == null) return null;
    
    // Direct ID (not a URL)
    if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
      return url;
    }
    
    try {
      // Standard YouTube URL patterns
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

  // Updates player to a new playlist
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    try {
      // Process each item for YouTube URLs
      final processedItems = <MediaItem>[];
      final audioSources = <AudioSource>[];
      
      for (final item in newQueue) {
        String? videoId = _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
        
        if (videoId != null) {
          // Handle YouTube video
          String? streamUrl;
          
          // Use YT-DLP service to get streaming URL
          try {
            final youtubeDlService = YoutubeDLService();
            streamUrl = await youtubeDlService.getStreamUrl(videoId);
            if (streamUrl != null) {
              _logger.info('Got streaming URL using YT-DLP service for video: $videoId');
            }
          } catch (e) {
            _logger.warning('Error using YT-DLP service: $e');
          }
          
          if (streamUrl != null) {
            final newItem = item.copyWith(
              id: streamUrl,
              extras: {...?item.extras, 'url': streamUrl},
            );
            
            processedItems.add(newItem);
            audioSources.add(AudioSource.uri(Uri.parse(streamUrl), tag: newItem));
          } else {
            _logger.warning('Could not find streaming URL for YouTube video: $videoId');
          }
        } else {
          // Regular audio URL
          processedItems.add(item);
          audioSources.add(AudioSource.uri(
            Uri.parse(item.extras?['url'] as String? ?? item.id),
            tag: item,
          ));
        }
      }
      
      // Update queue and playlist
      queue.add(processedItems);
      await _playlist.clear();
      await _playlist.addAll(audioSources);
    } catch (e) {
      _logger.severe('Error updating queue: $e');
    }
  }  Future<void> playMediaItem(MediaItem mediaItem, {bool isFromSearch = false}) async {
    // Prevent multiple simultaneous play requests
    if (_processingPlayRequest) {
      print('[DEBUG] playMediaItem - IGNORED (already processing) for: ${mediaItem.title}');
      return;
    }
    
    _processingPlayRequest = true;
    print('[DEBUG] playMediaItem - START for: ${mediaItem.title}');
    try {
      // If this is from search, mark it as the first search song
      if (isFromSearch && _firstSearchSong == null) {
        _firstSearchSong = mediaItem;
        print('[UP-NEXT DEBUG] Set first search song: ${mediaItem.title}');
      }
      
      final idx = queue.value.indexWhere((m) {
        final vid1 = m.extras?['videoId'] ?? _extractYouTubeVideoId(m.extras?['url'] as String? ?? m.id);
        final vid2 = mediaItem.extras?['videoId'] ?? _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
        return vid1 != null && vid1 == vid2;
      });

      // Apply current settings before playing
      await _applySettings();
      if (idx != -1) {
        print('[DEBUG] playMediaItem - Song found in queue at index $idx, seeking and playing: ${mediaItem.title}');
        await _player.seek(Duration.zero, index: idx);
        await _player.play();
      } else {
        print('[DEBUG] playMediaItem - Song not in queue, calling clearAndPlay for: ${mediaItem.title}');
        // Replace current playback with the chosen media item
        // Reset similar songs when playing from search, otherwise keep existing similar list
        await clearAndPlay(mediaItem, resetSimilar: isFromSearch, isFromSearch: isFromSearch);
        print('[DEBUG] playMediaItem - clearAndPlay COMPLETED for: ${mediaItem.title}');
      }
    } catch (e, st) {
      print('[DEBUG] playMediaItem - ERROR for: ${mediaItem.title}: $e');
      _logger.severe('Error in playMediaItem: $e');
      _logger.severe(st);
      // Notify the UI about the error
      final error = e.toString();
      if (error.contains('Permission denied') || error.contains('403')) {
        throw PlaybackException('This song is not available for playback.');
      } else if (error.contains('network')) {
        throw PlaybackException('Network error. Please check your connection.');
      } else {
        throw PlaybackException('Unable to play this song. Please try again later.');
      }
    } finally {
      _processingPlayRequest = false;
      print('[DEBUG] playMediaItem - END for: ${mediaItem.title}');
    }
  }

  // Method to play a specific song from the up-next list
  Future<void> playFromUpNext(int upNextIndex) async {
    try {
      if (upNextIndex < 0 || upNextIndex >= _latestSimilarSongs.length) {
        _logger.warning('Invalid up-next index: $upNextIndex');
        return;
      }
      
      final targetSong = _latestSimilarSongs[upNextIndex];
      print('[UP-NEXT DEBUG] Playing from up-next index $upNextIndex: ${targetSong.title}');
      
      // If it's the currently playing song, just ensure it's playing
      final currentSong = await mediaItem.first;
      if (currentSong != null) {
        final currentVideoId = currentSong.extras?['videoId'] as String? ??
            _extractYouTubeVideoId(currentSong.extras?['url'] as String? ?? currentSong.id);
        final targetVideoId = targetSong.extras?['videoId'] as String? ??
            _extractYouTubeVideoId(targetSong.extras?['url'] as String? ?? targetSong.id);
            
        if (currentVideoId == targetVideoId) {
          await play();
          return;
        }
      }
      
      // Check if the target song is already in the main queue
      final mainQueue = queue.value;
      final queueIndex = mainQueue.indexWhere((item) {
        final queueVideoId = item.extras?['videoId'] as String? ??
            _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
        final targetVideoId = targetSong.extras?['videoId'] as String? ??
            _extractYouTubeVideoId(targetSong.extras?['url'] as String? ?? targetSong.id);
        return queueVideoId == targetVideoId;
      });
      
      if (queueIndex != -1) {
        // Song is in main queue, skip to it
        await skipToQueueItem(queueIndex);
        await play();
      } else {
        // Song is not in main queue, play it directly
        await clearAndPlay(targetSong, resetSimilar: false);
      }
    } catch (e, stackTrace) {
      _logger.severe('Error playing from up-next: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
  }

  // Method to reset the first search song (useful when starting a new search session)
  void resetFirstSearchSong() {
    _firstSearchSong = null;
    print('[UP-NEXT DEBUG] Reset first search song');
  }
    // Method to clear the session and start fresh
  void clearSession() {
    _sessionFirstSong = null;
    _firstSearchSong = null;
    _latestSimilarSongs = [];
    _currentUpNextList = [];
    _nextSongsController.add([]);
    print('[UP-NEXT DEBUG] Cleared session');
  }

  // Remove a song from the up-next list
  void removeFromUpNext(String songId) {
    final currentList = _currentUpNextList.toList();
    currentList.removeWhere((item) {
      final itemVideoId = item.extras?['videoId'] as String? ??
          _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
      final targetVideoId = _extractYouTubeVideoId(songId) ?? songId;
      return itemVideoId == targetVideoId || item.id == songId;
    });
    
    _currentUpNextList = currentList;
    _latestSimilarSongs = currentList;
    _nextSongsController.add(currentList);
    print('[UP-NEXT DEBUG] Removed song from up-next list, new size: ${currentList.length}');
  }

  // Add songs to the main playlist for seamless next/previous functionality
  Future<void> _addNextSongsToPlaylist(List<MediaItem> songsToAdd) async {
    if (songsToAdd.isEmpty) return;
      print('[UP-NEXT DEBUG] Adding ${songsToAdd.length} songs to main playlist for seamless playback');
      // Add a delay to ensure the current song is properly loaded and playing first
    await Future.delayed(const Duration(seconds: 2));
    
    for (final item in songsToAdd) {
      try {
        String? videoId = item.extras?['videoId'] as String? ?? 
            _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
        String? streamUrl;

        if (videoId != null && videoId.length == 11) {
          // Get streaming URL for the song
          streamUrl = await _youtubeService.getStreamingUrl(videoId);
          if (streamUrl == null) {
            print('[UP-NEXT DEBUG] Failed to get stream URL for: ${item.title}');
            continue;
          }
        } else {
          // Use existing URL
          streamUrl = item.extras?['url'] as String? ?? item.id;
        }        // Create audio source and add to playlist
        final audioSource = AudioSource.uri(
          Uri.parse(streamUrl),
          tag: item.copyWith(id: streamUrl),
        );
        
        await _playlist.add(audioSource);
          // Add to queue
        final newQueue = queue.value..add(item.copyWith(
          id: streamUrl,
          extras: {
            ...?item.extras,
            'url': streamUrl,
          },
        ));
        queue.add(newQueue);
        
        print('[UP-NEXT DEBUG] Added to main playlist: ${item.title}');
        
        // Small delay between additions to prevent overwhelming the player
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('[UP-NEXT DEBUG] Error adding ${item.title} to playlist: $e');
        continue;
      }
    }
  }
}

class PlaybackException implements Exception {
  final String message;
  PlaybackException(this.message);
  @override
  String toString() => message;
}