import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:logging/logging.dart';

class YoutubeDLService {
  static final Logger _logger = Logger('YoutubeDLService');
  static final YoutubeDLService _instance = YoutubeDLService._internal();
  final YoutubeExplode _youtubeExplode = YoutubeExplode();

  factory YoutubeDLService() => _instance;

  YoutubeDLService._internal();

  Future<bool> isReady() async => true;

  final Map<String, String> _streamUrlCache = {};
  static const int _cacheSize = 20;

  Future<String?> getStreamUrl(String videoId) async {
    if (_streamUrlCache.containsKey(videoId)) {
      _logger.info('Returning cached stream URL for $videoId');
      return _streamUrlCache[videoId];
    }

    try {
      var manifest = await _youtubeExplode.videos.streamsClient.getManifest(videoId);
      var streamInfo = manifest.audioOnly.withHighestBitrate();
      var url = streamInfo.url.toString();

      if (url.isNotEmpty) {
        _logger.info('Got stream URL from youtube_explode_dart: $url');
        _cacheAndReturn(videoId, url);
        return url;
      } else {
        _logger.warning('youtube_explode_dart for $videoId produced invalid output');
      }
    } catch (e) {
      _logger.severe('Error getting stream URL for $videoId: $e');
    }

    _logger.severe('Failed to get stream URL for $videoId using all methods.');
    return null;
  }

  void _cacheAndReturn(String videoId, String url) {
    _streamUrlCache[videoId] = url;
    if (_streamUrlCache.length > _cacheSize) {
      _streamUrlCache.remove(_streamUrlCache.keys.first);
    }
  }
}