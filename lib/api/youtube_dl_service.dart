import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeDLService {
  static final Logger _logger = Logger('YoutubeDLService');
  static final YoutubeDLService _instance = YoutubeDLService._internal();
  
  factory YoutubeDLService() => _instance;
  
  YoutubeDLService._internal();
  
  // Only use youtube_explode_dart for extraction
  final YoutubeExplode _yt = YoutubeExplode();
  
  // Always ready (no initialization needed)
  Future<bool> isReady() async => true;
  
  // Simple in-memory cache for recent videoId→URL mappings
  final Map<String, String> _streamUrlCache = {};
  static const int _cacheSize = 20;

  // Get streaming URL for YouTube video ID using youtube_explode_dart
  Future<String?> getStreamUrl(String videoId) async {
    // Check cache first
    if (_streamUrlCache.containsKey(videoId)) {
      _logger.info('Returning cached stream URL for $videoId');
      return _streamUrlCache[videoId];
    }
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      // Get all audio-only streams, sorted by bitrate descending
      final audioStreams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      if (audioStreams.isEmpty) {
        _logger.warning('No audio stream found for $videoId');
        return null;
      }
      // Try each audio stream in order until one works
      for (final stream in audioStreams) {
        try {
          // Filter for preferred codecs (opus/webm, m4a)
          final mimeType = stream.codec.mimeType.toLowerCase();
          final codecString = stream.codec.toString().toLowerCase();
          if (!(mimeType.contains('audio') &&
                (codecString.contains('opus') || codecString.contains('aac') || codecString.contains('mp4a')))) {
            continue; // skip less preferred codecs
          }
          final url = stream.url.toString();
          // Optionally, do a HEAD request to check validity (skipped for speed)
          // Cache and return
          _streamUrlCache[videoId] = url;
          // Maintain cache size
          if (_streamUrlCache.length > _cacheSize) {
            _streamUrlCache.remove(_streamUrlCache.keys.first);
          }
          _logger.info('Got stream URL with youtube_explode_dart ($url)');
          return url;
        } catch (e) {
          _logger.warning('Failed to use audio stream for $videoId: $e');
          continue;
        }
      }
      _logger.warning('No usable audio stream found for $videoId');
      return null;
    } catch (e, stackTrace) {
      _logger.severe('Error getting stream URL: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    }
  }
}