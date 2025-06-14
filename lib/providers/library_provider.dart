import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:convert';

class LibraryProvider with ChangeNotifier {
  List<MediaItem> _recentlyPlayed = [];
  List<MediaItem> _favorites = [];
  Map<String, List<MediaItem>> _playlists = {};
  
  List<MediaItem> get recentlyPlayed => _recentlyPlayed;
  List<MediaItem> get favorites => _favorites;
  Map<String, List<MediaItem>> get playlists => _playlists;

  // Helper methods for MediaItem serialization
  Map<String, dynamic> _mediaItemToJson(MediaItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'album': item.album,
      'artUri': item.artUri?.toString(),
      'duration': item.duration?.inMilliseconds,
      'extras': item.extras,
    };
  }

  MediaItem _mediaItemFromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artUri: json['artUri'] != null ? Uri.parse(json['artUri'] as String) : null,
      duration: json['duration'] != null ? Duration(milliseconds: json['duration'] as int) : null,
      extras: json['extras'] as Map<String, dynamic>?,
    );
  }

  // Recently Played
  void addToRecentlyPlayed(MediaItem item) {
    _recentlyPlayed.remove(item);
    _recentlyPlayed.insert(0, item);
    if (_recentlyPlayed.length > 50) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, 50);
    }
    _saveRecentlyPlayed();
    notifyListeners();
  }

  // Favorites
  void toggleFavorite(MediaItem item) {
    final index = _favorites.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.add(item);
    }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavorite(MediaItem item) {
    return _favorites.any((i) => i.id == item.id);
  }

  // Playlists
  void createPlaylist(String name) {
    if (!_playlists.containsKey(name)) {
      _playlists[name] = [];
      _savePlaylists();
      notifyListeners();
    }
  }

  void addToPlaylist(String playlistName, MediaItem item) {
    if (_playlists.containsKey(playlistName) &&
        !_playlists[playlistName]!.any((i) => i.id == item.id)) {
      _playlists[playlistName]!.add(item);
      _savePlaylists();
      notifyListeners();
    }
  }

  void removeFromPlaylist(String playlistName, MediaItem item) {
    if (_playlists.containsKey(playlistName)) {
      _playlists[playlistName]!.removeWhere((i) => i.id == item.id);
      _savePlaylists();
      notifyListeners();
    }
  }

  void deletePlaylist(String name) {
    _playlists.remove(name);    _savePlaylists();
    notifyListeners();
  }

  // Persistence  
  Future<void> loadLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load favorites
    final favoritesJson = prefs.getStringList('favorites') ?? [];
    _favorites = favoritesJson
        .map((json) => _mediaItemFromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();

    // Load recently played
    final recentJson = prefs.getStringList('recently_played') ?? [];
    _recentlyPlayed = recentJson
        .map((json) => _mediaItemFromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();

    // Load playlists
    final playlistsJson = prefs.getString('playlists');
    if (playlistsJson != null) {
      final Map<String, dynamic> playlistsMap = jsonDecode(playlistsJson) as Map<String, dynamic>;
      _playlists = playlistsMap.map((key, value) {
        final List<dynamic> items = value;
        return MapEntry(
          key,
          items
              .map((item) => _mediaItemFromJson(Map<String, dynamic>.from(item)))
              .toList(),
        );
      });
    }

    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();    final favoritesJson = _favorites
        .map((item) => const JsonEncoder().convert(_mediaItemToJson(item)))
        .toList();
    await prefs.setStringList('favorites', favoritesJson);
  }

  Future<void> _saveRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();    final recentJson = _recentlyPlayed
        .map((item) => const JsonEncoder().convert(_mediaItemToJson(item)))
        .toList();
    await prefs.setStringList('recently_played', recentJson);
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final playlistsJson = const JsonEncoder().convert(_playlists.map((key, value) {
      return MapEntry(key, value.map((item) => _mediaItemToJson(item)).toList());
    }));
    await prefs.setString('playlists', playlistsJson);
  }
}
