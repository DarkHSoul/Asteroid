import 'dart:async';
import 'dart:convert';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/api/youtube_dl_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:logging/logging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class YouTubeService {
  static final Logger _logger = Logger('YouTubeService');

  // Singleton instance
  static final YouTubeService _instance = YouTubeService._internal();
  factory YouTubeService() => _instance;
  YouTubeService._internal();

  // Stream controller for connectivity status
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();

  // Expose connectivity stream
  Stream<bool> get connectivityStream => _connectivityController.stream;

  // Current connectivity status
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  // Keep track of processed video IDs
  final List<String> _processedVideoIds = [];
  List<String> get processedVideoIds => List.unmodifiable(_processedVideoIds);

  // Init method to setup connectivity monitoring
  Future<void> init() async {
    try {
      // Check initial connectivity
      _isConnected = await checkConnectivity();
      _connectivityController.add(_isConnected);

      // Set up listener for connectivity changes
      Connectivity().onConnectivityChanged.listen((ConnectivityResult result) async {
        final hasConnectivity = result != ConnectivityResult.none;
        if (_isConnected != hasConnectivity) {
          _isConnected = hasConnectivity;
          _connectivityController.add(_isConnected);
          _logger.info('Connectivity changed: $_isConnected');
        }
      });
    } catch (e) {
      _logger.severe('Error initializing YouTube service: $e');
    }
  }

  // Check if device has internet connectivity
  Future<bool> checkConnectivity() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _logger.severe('Error checking connectivity: $e');
      return false;
    }
  }

  // Search for YouTube Music videos
  Future<List<YoutubeMusicVideo>> search(String query) async {
    try {
      if (!await checkConnectivity()) {
        _logger.warning('No internet connectivity for search');
        return [];
      }
      
      return await YouTubeMusicApi.search(query);
    } catch (e) {
      _logger.severe('Error searching YouTube Music: $e');
      return [];
    }
  }

  // Get a direct streaming URL for a YouTube video using YT-DLP
  Future<String?> getStreamingUrl(String videoId) async {
    try {
      if (!await checkConnectivity()) {
        _logger.warning('No internet connectivity for streaming URL');
        return null;
      }
      
      _logger.info('Getting streaming URL for video ID: $videoId');
      
      // Add to processed IDs list
      if (!_processedVideoIds.contains(videoId)) {
        _processedVideoIds.add(videoId);
        _logger.info('Added video ID to processed list: $videoId');
        _logger.info('All processed video IDs: $_processedVideoIds');
      }
      
      // Use YT-DLP service to get streaming URL
      final youtubeDLService = YoutubeDLService();
      String? url;
      
      try {
        url = await youtubeDLService.getStreamUrl(videoId);
      } catch (e) {
        _logger.warning('Error using YoutubeDLService: $e');
      }
      
      // If YoutubeDLService fails, try direct Invidious API
      if (url == null) {
        _logger.info('YoutubeDLService failed, trying Invidious API directly');
        url = await _getStreamUrlFromInvidious(videoId);
      }
      
      if (url == null) {
        _logger.warning('Could not get streaming URL for video ID: $videoId');
        return null;
      }
      
      // Validate the URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        _logger.warning('Invalid URL format: $url');
        
        // Try to fix the URL
        if (url.startsWith('//')) {
          url = 'https:$url';
          _logger.info('Fixed URL by adding https: scheme');
        } else if (url.startsWith('/')) {
          url = 'https://music.youtube.com$url';
          _logger.info('Fixed URL by adding https://music.youtube.com scheme');
        } else {
          url = 'https://$url';
          _logger.info('Fixed URL by adding https:// scheme');
        }
      }
      
      // Validate the fixed URL
      try {
        final uri = Uri.parse(url);
        if (uri.scheme.isEmpty || (!uri.scheme.startsWith('http') && !uri.scheme.startsWith('https'))) {
          throw Exception('Invalid URL scheme: ${uri.scheme}');
        }
        _logger.info('Valid URL: scheme=${uri.scheme}, host=${uri.host}');
      } catch (e) {
        _logger.severe('URL validation failed: $e');
        return null;
      }
      
      _logger.info('Successfully obtained streaming URL for video ID: $videoId');
      return url;
    } catch (e, stackTrace) {
      _logger.severe('Error getting streaming URL: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    }
  }

  // Get streaming URL directly from Invidious API
  Future<String?> _getStreamUrlFromInvidious(String videoId) async {
    // List of public Invidious instances to try
    final invidousInstances = [
      'vid.puffyan.us',
      'invidious.snopyta.org',
      'invidious.kavin.rocks',
      'inv.riverside.rocks',
      'yt.artemislena.eu',
    ];
    
    // Try each Invidious instance
    for (final instance in invidousInstances) {
      try {
        final url = Uri.parse('https://$instance/api/v1/videos/$videoId');
        _logger.info('Trying Invidious API endpoint: $url');
        
        final response = await http.get(url).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _logger.info('Got response from Invidious API ($instance)');
          
          try {
            final data = json.decode(response.body);
            if (data['adaptiveFormats'] != null) {
              final formats = data['adaptiveFormats'] as List;
              _logger.info('Found ${formats.length} formats');
              
              // Find audio-only formats
              final audioFormats = formats.where((f) => 
                f['type']?.toString().contains('audio') == true
              ).toList();
              _logger.info('Found ${audioFormats.length} audio formats');
              
              if (audioFormats.isNotEmpty) {
                // Sort by bitrate (highest first)
                audioFormats.sort((a, b) => 
                  (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0)
                );
                
                // Get URL from best format
                for (final format in audioFormats) {
                  if (format['url'] != null) {
                    final streamUrl = format['url'].toString();
                    _logger.info('Got stream URL from Invidious API (${streamUrl.length} chars)');
                    return streamUrl;
                  }
                }
              }
            }
          } catch (e) {
            _logger.warning('Error parsing Invidious API response from $instance: $e');
          }
        } else {
          _logger.warning('Invidious API request to $instance failed with status: ${response.statusCode}');
        }
      } catch (e) {
        _logger.warning('Error with Invidious API request to $instance: $e');
      }
    }
    
    _logger.warning('All Invidious instances failed');
    return null;
  }

  // Print all processed video IDs
  void printProcessedVideoIds() {
    _logger.info('=== PROCESSED VIDEO IDs ===');
    for (int i = 0; i < _processedVideoIds.length; i++) {
      _logger.info('[$i]: ${_processedVideoIds[i]}');
    }
    _logger.info('=========================');
  }

  // Convert a YouTube Music video to a MediaItem for audio_service
  MediaItem youtubeVideoToMediaItem(YoutubeMusicVideo video) {
    return MediaItem(
      id: video.videoId,
      title: video.title,
      artist: video.artist,
      duration: _parseDuration(video.duration),
      artUri: Uri.parse(video.thumbnailUrl),
      extras: {
        'url': video.videoId, // We store the video ID, not the URL
        'source': 'youtube_music',
        'videoId': video.videoId, // Always include the original videoId
      },
    );
  }

  // Parse duration string (e.g. "3:45") to Duration
  Duration? _parseDuration(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return null;
    
    try {
      // Check if it's a seconds-only format
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        if (parts.length == 2) {
          // Format: MM:SS
          final minutes = int.parse(parts[0]);
          final seconds = int.parse(parts[1]);
          return Duration(minutes: minutes, seconds: seconds);
        } else if (parts.length == 3) {
          // Format: HH:MM:SS
          final hours = int.parse(parts[0]);
          final minutes = int.parse(parts[1]);
          final seconds = int.parse(parts[2]);
          return Duration(hours: hours, minutes: minutes, seconds: seconds);
        }
      } else {
        // Format: seconds only
        return Duration(seconds: int.parse(durationStr));
      }
    } catch (e) {
      _logger.warning('Error parsing duration: $durationStr - $e');
    }
    
    return null;
  }
  
  // Dispose resources
  void dispose() {
    _connectivityController.close();
  }
} 