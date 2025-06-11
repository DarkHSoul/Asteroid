import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  bool _processingPlayRequest = false;
  final _nextSongsController = StreamController<List<MediaItem>>.broadcast();
  Stream<List<MediaItem>> get nextSongsStream => _nextSongsController.stream;
  final YouTubeService _youtubeService = YouTubeService();

  MyAudioHandler() {
    print('MyAudioHandler initialized');
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    
    // Initialize the player with the playlist
    _initializePlayer();
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
    _player.currentIndexStream.listen((index) async {
      final playlist = queue.value;
      if (index == null || playlist.isEmpty) return;
      mediaItem.add(playlist[index]);
      final current = playlist[index];
      final videoId = current.extras?['videoId'] as String? ?? current.id;
      print('Triggering fetchSimilarSongs for videoId: $videoId');
      if (videoId != null && videoId.isNotEmpty) {
        final similarVideos = await YouTubeMusicApi.fetchSimilarSongs(videoId);
        final nextMediaItems = similarVideos.map((v) => _youtubeService.youtubeVideoToMediaItem(v)).toList();
        _nextSongsController.add(nextMediaItems);
        if (index == playlist.length - 1 && nextMediaItems.isNotEmpty) {
          final newQueue = List<MediaItem>.from(playlist)..addAll(nextMediaItems);
          await updateQueue(newQueue);
        }
      }
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

  // Initialize the player with the playlist
  Future<void> _initializePlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      _logger.info('Audio player initialized with playlist');
    } catch (e) {
      _logger.severe('Error initializing audio player: $e');
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    try {
      _logger.info('Adding queue item: ${mediaItem.title} - ${mediaItem.id}');
      
      // Get the URL from either id or extras
      String url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      
      if (url.isEmpty) {
        _logger.severe('Empty URL for media item: ${mediaItem.title}');
        throw Exception('Empty URL for media item');
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
          throw Exception('Missing scheme in URL');
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
          throw Exception('Invalid URL format: $url');
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
    if (_processingPlayRequest) {
      _logger.info('Already processing a play request, ignoring additional request');
      return;
    }
    
    _processingPlayRequest = true;
    
    try {
      // Check if we have any items in the playlist
      _logger.info('Playlist length: ${_playlist.length}');
      if (_playlist.length == 0) {
        _logger.warning('Attempted to play with empty playlist');
        return;
      }
      
      // Check if player has been properly initialized
      if (_player.audioSource == null) {
        _logger.info('Player not initialized, setting audio source');
        await _player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
      }
      
      // Now play
      _logger.info('Starting playback');
      await _player.play();
      _logger.info('Playback started successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error in play method: $e');
      _logger.severe('Stack trace: $stackTrace');
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
    _player.seek(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.children.length) return;
    _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToNext() async {
    final currentIndex = _player.currentIndex;
    final playlist = queue.value;
    if (currentIndex == null || playlist.isEmpty) return;
    final current = playlist[currentIndex];
    final videoId = current.extras?['videoId'] as String? ?? current.id;
    if (videoId != null && videoId.isNotEmpty) {
      final similarVideos = await YouTubeMusicApi.fetchSimilarSongs(videoId);
      final nextMediaItems = similarVideos.map((v) => _youtubeService.youtubeVideoToMediaItem(v)).toList();
      if (nextMediaItems.isNotEmpty) {
        final newQueue = List<MediaItem>.from(playlist)..add(nextMediaItems.first);
        await updateQueue(newQueue);
        await _player.seek(Duration.zero, index: newQueue.length - 1);
        _nextSongsController.add(nextMediaItems);
        return;
      }
    }
    if (_player.hasNext) {
      await _player.seekToNext();
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
  }
} 