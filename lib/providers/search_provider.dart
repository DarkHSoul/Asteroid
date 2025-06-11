import 'package:flutter/material.dart';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/services/audio_cache_service.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  List<YoutubeMusicVideo> _results = [];
  bool _isLoading = false;
  final AudioCacheService _audioCacheService = AudioCacheService();

  String get query => _query;
  List<YoutubeMusicVideo> get results => _results;
  bool get isLoading => _isLoading;

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setResults(List<YoutubeMusicVideo> value) {
    _results = value;
    notifyListeners();
    _preloadAudioForResults(value);
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clear() {
    _query = '';
    _results = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _preloadAudioForResults(List<YoutubeMusicVideo> results) async {
    // Limit to first 3 for demo; adjust as needed
    for (final video in results.take(3)) {
      final audioUrl = 'https://www.youtube.com/watch?v=${video.videoId}';
      // If you have a direct audio URL, use it instead
      try {
        await _audioCacheService.downloadAudio(audioUrl, video.videoId);
      } catch (e) {
        // Optionally handle download errors
      }
    }
  }
}
