import 'package:flutter/foundation.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // Removed
import 'package:asteroid/api/youtube_api_service.dart'; // Updated import
// import 'dart:convert'; // Removed

enum SearchFilter {
  all,
  songs,
  artists,
  albums,
  playlists,
}

// class CachedSearch { // Removed
//   final String query;
//   final List<YoutubeMusicVideo> results;
//   final DateTime timestamp;
//
//   CachedSearch({
//     required this.query,
//     required this.results,
//     required this.timestamp,
//   });
//
//   Map<String, dynamic> toJson() => {
//     'query': query,
//     'results': results.map((r) => r.toJson()).toList(),
//     'timestamp': timestamp.toIso8601String(),
//   };
//
//   factory CachedSearch.fromJson(Map<String, dynamic> json) {
//     return CachedSearch(
//       query: json['query'] as String,
//       results: (json['results'] as List)
//           .map((r) => YoutubeMusicVideo.fromJson(r as Map<String, dynamic>))
//           .toList(),
//       timestamp: DateTime.parse(json['timestamp'] as String),
//     );
//   }
// }

class SearchProvider with ChangeNotifier {
  String _query = '';
  List<YoutubeMusicVideo> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _continuationToken;
  SearchFilter _currentFilter = SearchFilter.all;
  // Map<String, CachedSearch> _searchCache = {}; // Removed
  List<YoutubeMusicVideo> _relatedSongs = [];
  // Set<String> _playingVideoIds = {}; // Removed: State will be handled by AudioHandler
  
  // static const int _maxCacheAge = 3600; // Removed
  // static const int _maxCacheEntries = 50; // Removed

  String get query => _query;
  List<YoutubeMusicVideo> get results => _getFilteredResults();
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get continuationToken => _continuationToken;
  SearchFilter get currentFilter => _currentFilter;
  List<YoutubeMusicVideo> get relatedSongs => _relatedSongs;
  // bool isPlaying(String videoId) => _playingVideoIds.contains(videoId); // Removed

  // SearchProvider() { // Removed constructor content
  //   // _loadCache();
  // }
  List<YoutubeMusicVideo> _getFilteredResults() {
    debugPrint('Filtering results with filter: $_currentFilter');
    switch (_currentFilter) {
      case SearchFilter.songs:
        return _results.where((result) => !result.isArtist && !result.isAlbum && !result.isPlaylist).toList();
      case SearchFilter.artists:
        return _results.where((result) => result.isArtist).toList();
      case SearchFilter.albums:
        return _results.where((result) => result.isAlbum).toList();
      case SearchFilter.playlists:
        return _results.where((result) => result.isPlaylist).toList();
      case SearchFilter.all:
        return _results;
    }
  }

  void setFilter(SearchFilter filter) {
    _currentFilter = filter;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void setResults(List<YoutubeMusicVideo> results, {String? continuation}) {
    _results = results;
    _continuationToken = continuation;
    // _cacheResults(); // Removed
    notifyListeners();
  }

  void appendResults(List<YoutubeMusicVideo> more, {String? continuation}) {
    _results.addAll(more);
    _continuationToken = continuation;
    // _cacheResults(); // Removed
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setLoadingMore(bool loading) {
    _isLoadingMore = loading;
    notifyListeners();
  }

  void updateRelatedSongs(List<YoutubeMusicVideo> songs) {
    _relatedSongs = songs;
    notifyListeners();
  }

  // void setPlayingState(String videoId, bool isPlaying) { // Removed
  //   if (isPlaying) {
  //     _playingVideoIds.add(videoId);
  //   } else {
  //     _playingVideoIds.remove(videoId);
  //   }
  //   notifyListeners();
  // }

  // Future<void> _loadCache() async { // Removed
  //   try {
  //     final prefs = await SharedPreferences.getInstance();
  //     final cacheJson = prefs.getString('search_cache');
  //     if (cacheJson != null) {
  //       final Map<String, dynamic> cacheMap = json.decode(cacheJson);
  //       _searchCache = cacheMap.map((key, value) => MapEntry(
  //         key,
  //         CachedSearch.fromJson(value as Map<String, dynamic>),
  //       ));
  //       _cleanCache();
  //     }
  //   } catch (e) {
  //     debugPrint('Error loading search cache: $e');
  //   }
  // }

  // Future<void> _cacheResults() async { // Removed
  //   if (_query.isEmpty || _results.isEmpty) return;
  //
  //   try {
  //     _searchCache[_query] = CachedSearch(
  //       query: _query,
  //       results: _results,
  //       timestamp: DateTime.now(),
  //     );
  //     _cleanCache();
  //
  //     final prefs = await SharedPreferences.getInstance();
  //     final cacheJson = json.encode(_searchCache);
  //     await prefs.setString('search_cache', cacheJson);
  //   } catch (e) {
  //     debugPrint('Error caching search results: $e');
  //   }
  // }

  // void _cleanCache() { // Removed
  //   final now = DateTime.now();
  //   _searchCache.removeWhere((_, cache) =>
  //       now.difference(cache.timestamp).inSeconds > _maxCacheAge);
  //   
  //   if (_searchCache.length > _maxCacheEntries) {
  //     final sortedEntries = _searchCache.entries.toList()
  //       ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
  //     _searchCache = Map.fromEntries(sortedEntries.take(_maxCacheEntries));
  //   }
  // }

  List<YoutubeMusicVideo>? getCachedResults(String query) { // Modified to always return null
    // final cached = _searchCache[query];
    // if (cached != null &&
    //     DateTime.now().difference(cached.timestamp).inSeconds <= _maxCacheAge) {
    //   return cached.results;
    // }
    return null;
  }

  void clearCache() { // Modified to do nothing relevant to file cache
    // _searchCache.clear();
    // SharedPreferences.getInstance().then((prefs) {
    //   prefs.remove('search_cache');
    // });
    notifyListeners();
  }
}
