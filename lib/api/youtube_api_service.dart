import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform; // Conditionally used
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for local storage
import 'package:audio_service/audio_service.dart'; // For MediaItem conversion
import 'package:asteroid/api/youtube_dl_service.dart'; // Added import for YoutubeDLService

// --- Data Class (from former YouTubeMusicApi) ---
class YoutubeMusicVideo {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String duration;
  final int? viewCount;
  String? trackingParams;
  String? playlistId;
  String? params;
  final bool isArtistItem;
  final bool isAlbumItem;
  final bool isPlaylistItem; // Added for playlists

  YoutubeMusicVideo({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.viewCount,
    this.trackingParams,
    this.playlistId,
    this.params,
    this.isArtistItem = false,
    this.isAlbumItem = false,
    this.isPlaylistItem = false, // Added for playlists
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'duration': duration,
    'viewCount': viewCount,
    'trackingParams': trackingParams,
    'playlistId': playlistId,
    'params': params,
    'isArtistItem': isArtistItem,
    'isAlbumItem': isAlbumItem,
    'isPlaylistItem': isPlaylistItem, // Added for playlists
  };

  factory YoutubeMusicVideo.fromJson(Map<String, dynamic> json) {
    return YoutubeMusicVideo(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      duration: json['duration'] as String,
      viewCount: json['viewCount'] as int?,
      trackingParams: json['trackingParams'] as String?,
      playlistId: json['playlistId'] as String?,
      params: json['params'] as String?,
      isArtistItem: json['isArtistItem'] as bool? ?? false,
      isAlbumItem: json['isAlbumItem'] as bool? ?? false,
      isPlaylistItem: json['isPlaylistItem'] as bool? ?? false, // Added for playlists
    );
  }

  bool get isArtist => isArtistItem;
  bool get isAlbum => isAlbumItem;
  bool get isPlaylist => isPlaylistItem; // Added for playlists
}

// --- Unified YouTube API Service ---
class YouTubeApiService {
  static final Logger _logger = Logger('YouTubeApiService');

  // --- Singleton Pattern (from former YouTubeService) ---
  static final YouTubeApiService _instance = YouTubeApiService._internal();
  factory YouTubeApiService() => _instance;
  YouTubeApiService._internal();

  // --- Connectivity (from former YouTubeService) ---
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  Future<void> initConnectivity() async {
    try {
      _isConnected = await _checkConnectivityStatus();
      _connectivityController.add(_isConnected);
      Connectivity().onConnectivityChanged.listen((ConnectivityResult result) async {
        final hasConnectivity = result != ConnectivityResult.none;
        if (_isConnected != hasConnectivity) {
          _isConnected = hasConnectivity;
          _connectivityController.add(_isConnected);
          _logger.info('Connectivity changed: $_isConnected');
        }
      });
    } catch (e) {
      _logger.severe('Error initializing connectivity: $e');
    }
  }

  Future<bool> _checkConnectivityStatus() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _logger.severe('Error checking connectivity status: $e');
      return false;
    }
  }

  // --- API Constants (from former YouTubeMusicApi) ---
  static const String _musicApiDomain = 'music.youtube.com';
  static const String _youtubeApiDomain = 'www.youtube.com'; // For player API if needed
  
  static const String _baseApiPath = '/youtubei/v1';
  static const String _searchEndpointPath = '/search';
  static const String _nextEndpointPath = '/next';
  static const String _playerEndpointPath = '/player'; // For playback details

  static final String _proxyBaseUrl = () {
    if (kIsWeb) {
      return 'http://localhost:8080';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8080';
      }
    } catch (e) {
      // Fallback for desktop and other platforms
    }
    return 'http://localhost:8080';
  }();

  static final String _nodeServerBaseUrl = '${_proxyBaseUrl}/api/youtubei/v1'; // For Web/Windows proxy

  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
  static const String _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  
  static const Map<String, String> _defaultHeaders = {
    'User-Agent': _userAgent,
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/json',
    'Origin': 'https://$_musicApiDomain',
    'Referer': 'https://$_musicApiDomain/',
    'X-Youtube-Client-Name': '67',
    'X-Youtube-Client-Version': '1.20250602.03.00',
    'X-Origin': 'https://$_musicApiDomain',
  };

  // --- Platform-dependent Proxy Logic ---
  static bool get _shouldUseProxy {
    if (kIsWeb) return true;
    try {
      if (Platform.isWindows) return true;
      return false; 
    } catch (e) {
      _logger.warning('Error checking platform for proxy: $e. Defaulting to no proxy.');
      return false; 
    }
  }
  
  static String _getApiEndpointUrl(String specificPath) {
    if (_shouldUseProxy) {
      return '$_nodeServerBaseUrl$specificPath'; 
    } else {
      return 'https://$_musicApiDomain$_baseApiPath$specificPath';
    }
  }

  // --- Client Context for Direct API Calls ---
  static Map<String, dynamic> _buildDirectApiContext() {
    return {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': _defaultHeaders['X-Youtube-Client-Version']!,
        'hl': 'en',
        'gl': 'US',
        'userAgent': _userAgent,
        'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
        'browserName': 'Chrome',
        'browserVersion': '121.0.0.0',
        'osName': 'Windows',
        'osVersion': '10.0',
        'platform': 'DESKTOP',
      },
      'user': {'lockedSafetyMode': false},
      'request': {
        'useSsl': true,
        'internalExperimentFlags': [],
        'consistencyTokenJars': []
      },
    };
  }

  // --- Search Functionality ---
  static String? _lastSearchContinuationToken;
  static String? get lastSearchContinuationToken => _lastSearchContinuationToken;

  Future<List<YoutubeMusicVideo>> searchMusic(String query) async {
    if (!await _checkConnectivityStatus()) {
      _logger.warning('Network not available for search');
      return [];
    }
    final String urlString = _getApiEndpointUrl(_searchEndpointPath);
    final Uri url = Uri.parse(urlString).replace(queryParameters: {'key': _apiKey});
    Object requestBodyForHttp;
    if (_shouldUseProxy) {
      requestBodyForHttp = json.encode({'query': query});
      _logger.info('Search: Using Proxy. URL: $url. Body: ${json.encode({'query': query})}');
    } else {
      final directApiRequestBody = {'context': _buildDirectApiContext(), 'query': query};
      requestBodyForHttp = json.encode(directApiRequestBody);
      _logger.info('Search: Direct Call. URL: $url.');
    }
    try {
      final response = await http.post(url, headers: _defaultHeaders, body: requestBodyForHttp).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        _logger.info('Search: Received 200 OK.');
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final videos = _parseSearchResponse(jsonResponse);
        _lastSearchContinuationToken = _extractContinuationToken(jsonResponse);
        return videos;
      } else {
        _logger.warning('Search: Failed. Status: ${response.statusCode}. Body: ${response.body.substring(0,_min(response.body.length, 300))}');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.severe('Search: Error. $e', e, stackTrace);
      return [];
    }
  }
  
  Future<List<YoutubeMusicVideo>> searchMusicContinuation(String token) async {
    if (token.isEmpty) return [];
    if (!await _checkConnectivityStatus()) return [];
    final String urlString = _getApiEndpointUrl(_searchEndpointPath);
    final Uri url = Uri.parse(urlString).replace(queryParameters: {'key': _apiKey});
    Object requestBodyForHttp;
    if (_shouldUseProxy) {
      requestBodyForHttp = json.encode({'continuation': token});
      _logger.info('SearchContinuation: Using Proxy. URL: $url. Body: ${json.encode({'continuation': token})}');
    } else {
      final directApiRequestBody = {'context': _buildDirectApiContext(), 'continuation': token};
      requestBodyForHttp = json.encode(directApiRequestBody);
      _logger.info('SearchContinuation: Direct Call. URL: $url.');
    }
    try {
      final response = await http.post(url, headers: _defaultHeaders, body: requestBodyForHttp).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        _logger.info('SearchContinuation: Received 200 OK.');
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final videos = _parseSearchResponse(jsonResponse);
        _lastSearchContinuationToken = _extractContinuationToken(jsonResponse);
        return videos;
      } else {
        _logger.warning('SearchContinuation: Failed. Status: ${response.statusCode}. Body: ${response.body.substring(0,_min(response.body.length, 300))}');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.severe('SearchContinuation: Error. $e', e, stackTrace);
      return [];
    }
  }

  static String? _extractContinuationToken(Map<String, dynamic> jsonResponse) {
    try {
      final tabs = jsonResponse['contents']?['tabbedSearchResultsRenderer']?['tabs'];
      if (tabs is List) {
        for (final tab in tabs) {
          final token = tab?['tabRenderer']?['content']?['sectionListRenderer']?['continuations']?[0]?['nextContinuationData']?['token'];
          if (token != null && token is String && token.isNotEmpty) return token;
        }
      }
    } catch (e) {
      _logger.warning('Error extracting search continuation token: $e');
    }
    return null;
  }
  
  static List<YoutubeMusicVideo> _parseSearchResponse(Map<String, dynamic> response) {
    final List<YoutubeMusicVideo> videos = [];
    try {
      final tabbedResults = response['contents']?['tabbedSearchResultsRenderer'];
      if (tabbedResults == null || tabbedResults['tabs'] == null) return videos;
      final tabs = tabbedResults['tabs'] as List;
      for (final tab in tabs) {
        final sectionListRenderer = tab['tabRenderer']?['content']?['sectionListRenderer'];
        if (sectionListRenderer == null || sectionListRenderer['contents'] == null) continue;
        final contents = sectionListRenderer['contents'] as List;
        for (final section in contents) {
          if (section['musicShelfRenderer'] != null && section['musicShelfRenderer']['contents'] != null) {
            final items = section['musicShelfRenderer']['contents'] as List;
            for (final item in items) {
              if (item['musicResponsiveListItemRenderer'] != null) {
                final video = _extractVideoFromRenderer(item['musicResponsiveListItemRenderer']);
                if (video != null) videos.add(video);
              }
            }
          }
        }
      }
      _logger.info('Parsed ${videos.length} videos from search response.');
    } catch (e, stackTrace) {
      _logger.severe('Error parsing search response: $e', e, stackTrace);
    }
    return videos;
  }

  static YoutubeMusicVideo? _extractVideoFromRenderer(Map<String, dynamic> renderer) {
    // This is an attempt to restore the method to its state *before* the artist/album parsing logic was added,
    // Re-implementing artist/album parsing carefully.
    try {
      String videoId = '';
      String? playlistId;
      String? params;
      bool isItemArtist = false;
      bool isItemAlbum = false;
      bool isItemPlaylist = false; // Added for playlists
      String itemTypeBrowseId = '';
      
      final dynamic playNavigationEndpointData = renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
      
      if (playNavigationEndpointData is Map<String, dynamic>) {
        final Map<String, dynamic> playNavEndpoint = playNavigationEndpointData;
        if (playNavEndpoint['watchEndpoint']?['videoId'] != null) {
          videoId = playNavEndpoint['watchEndpoint']['videoId'] as String;
          playlistId = playNavEndpoint['watchEndpoint']['playlistId'] as String?;
          params = playNavEndpoint['watchEndpoint']['params'] as String?;
        } else if (playNavEndpoint['watchPlaylistEndpoint']?['playlistId'] != null) {
          // This is a playlist, capture its ID
          playlistId = playNavEndpoint['watchPlaylistEndpoint']['playlistId'] as String;
          videoId = playlistId!; // Use playlistId as the main ID for playlist items
          isItemPlaylist = true;
          _logger.fine('Identified Playlist (via overlay): $playlistId, Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
        }
      }

      if (videoId.isEmpty) { // If not found via overlay, check navigationEndpoint
        final dynamic navigationEndpointData = renderer['navigationEndpoint'];
        if (navigationEndpointData is Map<String, dynamic>) {
            final dynamic browseEndpointRaw = navigationEndpointData['browseEndpoint'];
            if (browseEndpointRaw is Map<String, dynamic> && browseEndpointRaw['browseId'] != null) {
                final Map<String, dynamic> browseEndpointData = browseEndpointRaw;
                itemTypeBrowseId = browseEndpointData['browseId'] as String;
                
                String? pageType;
                final dynamic supportedConfigs = browseEndpointData['browseEndpointContextSupportedConfigs'];
                if (supportedConfigs is Map<String, dynamic>) {
                    final dynamic musicConfig = supportedConfigs['browseEndpointContextMusicConfig'];
                    if (musicConfig is Map<String, dynamic>) {
                        pageType = musicConfig['pageType'] as String?;
                    }
                }

                if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
                    isItemAlbum = true;
                    videoId = itemTypeBrowseId;
                    _logger.fine('Identified Album: $videoId, Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
                } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
                    isItemArtist = true;
                    videoId = itemTypeBrowseId;
                    _logger.fine('Identified Artist: $videoId, Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
                } else if (itemTypeBrowseId.startsWith('VL') || pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' || pageType == 'MUSIC_PAGE_TYPE_USER_CHANNEL') { // Check for playlist browseId or pageType
                    isItemPlaylist = true;
                    videoId = itemTypeBrowseId; // Use browseId as videoId for playlists
                    playlistId = itemTypeBrowseId; // Also store it as playlistId
                    _logger.fine('Identified Playlist (via browseId/pageType): $videoId, Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
                } else {
                    _logger.finer('Unknown/unhandled browse item type: $pageType, browseId: $itemTypeBrowseId. Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
                }
            }
        }
      }
      
      if (videoId.isEmpty) {
        _logger.warning('Failed to extract a usable videoId or browseId. Title: ${renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']}');
        return null;
      }

      String title = renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text'] ?? '';
      if (title.isEmpty) {
        _logger.warning('Failed to extract title for videoId/browseId: $videoId');
        return null;
      }

      String artist = '';
      String duration = '';
      String year = ''; // For albums
      String trackCount = ''; // For albums

      final dynamic flexColumn1Runs = renderer['flexColumns']?[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      if (flexColumn1Runs is List) {
        List<String> artistParts = [];
        for (final dynamic runItem in flexColumn1Runs) {
          if (runItem is Map<String, dynamic>) {
            final String? text = runItem['text'] as String?;
            if (text == null || text.trim() == '•' || text.trim().isEmpty) continue;

            if (isItemAlbum) {
              if (text.toLowerCase() == 'album' || text.toLowerCase() == 'single') {
                // Type indicator, skip
              } else if (RegExp(r'^\d{4}$').hasMatch(text) && year.isEmpty) {
                year = text;
              } else if (text.toLowerCase().contains('song') && trackCount.isEmpty) {
                trackCount = text; // e.g., "10 songs"
              } else {
                artistParts.add(text); // Artist name for the album
              }
            } else if (isItemArtist) {
              // For artists, flexColumn1 might contain subscriber count or "Artist" label
              if (text.toLowerCase() != 'artist') {
                 duration += (duration.isEmpty ? '' : ' • ') + text; // Store other info like sub count in duration field for artists
              }
            } else { // Song
              if (!RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(text) && text.toLowerCase() != title.toLowerCase()) {
                artistParts.add(text);
              } else {
                duration = text;
              }
            }
          }
        }
        if (artistParts.isNotEmpty) {
          artist = artistParts.join(', ');
        }
        
        if (isItemAlbum) { // For albums, duration field will store year and track count
            duration = year;
            if (trackCount.isNotEmpty) {
                duration += (duration.isEmpty ? '' : ' • ') + trackCount;
            }
        }
      }
      
      String thumbnailUrl = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']?.last?['url'] ?? '';
      if (thumbnailUrl.startsWith('//')) {
        thumbnailUrl = 'https:$thumbnailUrl';
      }

      if (_shouldUseProxy && thumbnailUrl.isNotEmpty) {
        try {
          // Ensure the URL is valid before trying to encode it
          Uri.parse(thumbnailUrl); // This will throw if the URL is invalid
          thumbnailUrl = '${_proxyBaseUrl}/api/image-proxy?url=${Uri.encodeComponent(thumbnailUrl)}';
          _logger.finer('Using proxied thumbnail URL: $thumbnailUrl');
        } catch (e) {
          _logger.warning('Invalid thumbnail URL, cannot proxy: ${renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']?.last?['url'] ?? ''} - Error: $e');
          thumbnailUrl = ''; // Set to empty if invalid to avoid further errors
        }
      }
      
      String? trackingParams = renderer['trackingParams'] as String?;

      return YoutubeMusicVideo(
        videoId: videoId,
        title: title,
        artist: artist.trim(),
        thumbnailUrl: thumbnailUrl,
        duration: duration.trim(),
        playlistId: playlistId,
        params: params,
        trackingParams: trackingParams,
        isArtistItem: isItemArtist,
        isAlbumItem: isItemAlbum,
      );
    } catch (e, stackTrace) {
      _logger.severe('Error in _extractVideoFromRenderer (re-implementing artist/album): $e', e, stackTrace);
      return null;
    }
  }

  static String? _extractAutomixPlaylistId(Map<String, dynamic> jsonResponse) {
    try {
      final contents = jsonResponse['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents'];
      if (contents is List) {
        for (final item in contents) {
          if (item['automixPreviewVideoRenderer'] != null) {
            final playlistId = item['automixPreviewVideoRenderer']?['content']?['automixPlaylistVideoRenderer']?['navigationEndpoint']?['watchPlaylistEndpoint']?['playlistId'];
            if (playlistId is String && playlistId.isNotEmpty) {
              return playlistId;
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Error extracting automix playlist ID: $e');
    }
    return null;
  }

  Future<({List<YoutubeMusicVideo> videos, String? continuationToken})?> fetchSimilarSongs(String videoId, {String? playlistId, String? params}) async {
    if (!await _checkConnectivityStatus()) return null;
    final String urlString = _getApiEndpointUrl(_nextEndpointPath);
    final Uri url = Uri.parse(urlString).replace(queryParameters: {'key': _apiKey});
    
    Map<String, dynamic> payloadForNode = {'videoId': videoId, 'isAudioOnly': true};
    if (playlistId != null && playlistId.isNotEmpty) payloadForNode['playlistId'] = playlistId;
    if (params != null && params.isNotEmpty) payloadForNode['params'] = params;
    
    Object requestBodyForHttp;
    if (_shouldUseProxy) {
      requestBodyForHttp = json.encode(payloadForNode);
      _logger.info('fetchSimilarSongs: Using Proxy. URL: $url. Body: ${json.encode(payloadForNode)}');
    } else {
      final directApiRequestBody = {'context': _buildDirectApiContext(), ...payloadForNode};
      requestBodyForHttp = json.encode(directApiRequestBody);
      _logger.info('fetchSimilarSongs: Direct Call. URL: $url.');
    }

    try {
      final response = await http.post(url, headers: _defaultHeaders, body: requestBodyForHttp).timeout(const Duration(seconds: 15));
      _logger.info('fetchSimilarSongs: Response Status: ${response.statusCode}');
      if (response.statusCode != 200) {
        _logger.warning('fetchSimilarSongs: Failed. Full Response Body: ${response.body}');
        return null;
      }
      
      _logger.info('fetchSimilarSongs: Successful Raw Response Body (first 2000 chars): ${response.body.substring(0, _min(response.body.length, 2000))}');
      final Map<String, dynamic> jsonResponse = json.decode(response.body);

      final String? automixPlaylistId = _extractAutomixPlaylistId(jsonResponse);
      if (automixPlaylistId != null) {
        _logger.info('Found automix playlist ID: $automixPlaylistId. Fetching its content now.');
        final newPayload = {'playlistId': automixPlaylistId, 'isAudioOnly': true};
        Object newRequestBody;
        if (_shouldUseProxy) {
          newRequestBody = json.encode(newPayload);
          _logger.info('fetchSimilarSongs(automix): Using Proxy. URL: $url. Body: ${json.encode(newPayload)}');
        } else {
          final directApiRequestBody = {'context': _buildDirectApiContext(), ...newPayload};
          newRequestBody = json.encode(directApiRequestBody);
          _logger.info('fetchSimilarSongs(automix): Direct Call. URL: $url.');
        }
        
        final newResponse = await http.post(url, headers: _defaultHeaders, body: newRequestBody).timeout(const Duration(seconds: 15));
        if (newResponse.statusCode == 200) {
          final newJsonResponse = json.decode(newResponse.body);
          return _parseNextResponse(newJsonResponse);
        } else {
          _logger.warning('Failed to fetch automix playlist content. Status: ${newResponse.statusCode}');
          return null;
        }
      }

      _logger.info('fetchSimilarSongs: No automix playlist found, parsing current response. Top-level keys: ${jsonResponse.keys.toList()}');
      return _parseNextResponse(jsonResponse);

    } catch (e, stackTrace) {
      _logger.severe('fetchSimilarSongs: Error. $e', e, stackTrace);
      return null;
    }
  }

  Future<({List<YoutubeMusicVideo> videos, String? continuationToken})?> fetchNextContinuation(String token) async {
    if (token.isEmpty) return null;
    if (!await _checkConnectivityStatus()) return null;
    final String urlString = _getApiEndpointUrl(_nextEndpointPath);
    final Uri url = Uri.parse(urlString).replace(queryParameters: {'key': _apiKey});
    Object requestBodyForHttp;
    if (_shouldUseProxy) {
      requestBodyForHttp = json.encode({'continuation': token});
      _logger.info('fetchNextContinuation: Using Proxy. URL: $url. Body: ${json.encode({'continuation': token})}');
    } else {
      final directApiRequestBody = {'context': _buildDirectApiContext(), 'continuation': token};
      requestBodyForHttp = json.encode(directApiRequestBody);
      _logger.info('fetchNextContinuation: Direct Call. URL: $url.');
    }
    try {
      final response = await http.post(url, headers: _defaultHeaders, body: requestBodyForHttp).timeout(const Duration(seconds: 15));
      _logger.info('fetchNextContinuation: Response Status: ${response.statusCode}');
      if (response.statusCode != 200) {
        _logger.warning('fetchNextContinuation: Failed. Full Response Body: ${response.body}');
      } else {
        _logger.info('fetchNextContinuation: Successful Raw Response Body (first 2000 chars): ${response.body.substring(0, _min(response.body.length, 2000))}');
      }
      
      if (response.statusCode == 200) {
        _logger.info('fetchNextContinuation: Received 200 OK.');
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
         _logger.info('fetchNextContinuation: Parsed JSON response. Top-level keys: ${jsonResponse.keys.toList()}');
        return _parseNextResponse(jsonResponse); // Removed '' (currentVideoIdToExclude)
      } else {
        // Already logged full body above if failed
        return null;
      }
    } catch (e, stackTrace) {
      _logger.severe('fetchNextContinuation: Error. $e', e, stackTrace);
      return null;
    }
  }
  
  static ({List<YoutubeMusicVideo> videos, String? continuationToken}) _parseNextResponse(Map<String, dynamic> jsonResponse) {
    final List<YoutubeMusicVideo> list = [];
    String? continuationToken;
    try {
      dynamic playlistPanel = jsonResponse['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer'];

      if (jsonResponse['continuationContents'] != null) {
        playlistPanel = jsonResponse['continuationContents']?['playlistPanelContinuation'];
      }

      if (playlistPanel == null) {
        _logger.warning('_parseNextResponse: Could not find a "playlistPanelRenderer" or "playlistPanelContinuation" in the response.');
        return (videos: list, continuationToken: null);
      }

      continuationToken = playlistPanel['continuations']?[0]?['nextContinuationData']?['token'] as String?;
      _logger.info('_parseNextResponse: Extracted continuation token: $continuationToken');

      final List<dynamic>? topLevelContents = playlistPanel['contents'] as List?;
      
      if (topLevelContents == null) {
        _logger.warning('_parseNextResponse: Could not find a "contents" array in the response.');
        return (videos: list, continuationToken: continuationToken);
      }
      _logger.info('_parseNextResponse: Found ${topLevelContents.length} raw items in the main contents array.');

      final Set<String> addedVideoIds = {};

      void parseAndAddVideo(dynamic videoRenderer) {
        if (videoRenderer == null) return;

        final String? videoId = videoRenderer['videoId'] as String?;
        if (videoId == null || videoId.isEmpty || addedVideoIds.contains(videoId)) {
          return;
        }
        
        final String title = videoRenderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown Title';
        String artist = 'Unknown Artist';
        final bylineRuns = videoRenderer['longBylineText']?['runs'] as List?;
        if (bylineRuns != null && bylineRuns.isNotEmpty) {
          artist = bylineRuns
              .map((r) => r['text'] as String?)
              .where((text) => text != null && text.trim() != '•')
              .join(' ');
          if (artist.trim().isEmpty) artist = 'Unknown Artist';
        }

        String thumbnailUrl = '';
        final thumbList = videoRenderer['thumbnail']?['thumbnails'] as List?;
        if (thumbList != null && thumbList.isNotEmpty) {
          thumbnailUrl = thumbList.last['url'] as String? ?? '';
           if (_shouldUseProxy && thumbnailUrl.isNotEmpty) {
            try {
              Uri.parse(thumbnailUrl); 
              thumbnailUrl = '${_proxyBaseUrl}/api/image-proxy?url=${Uri.encodeComponent(thumbnailUrl)}';
            } catch (e) {
              _logger.warning('Invalid thumbnail URL for proxy in _parseNextResponse: $thumbnailUrl - Error: $e');
              thumbnailUrl = ''; 
            }
          }
        }
        
        final String duration = videoRenderer['lengthText']?['runs']?[0]?['text'] as String? ?? '0:00';
        String? plId;
        String? prm;
        final navEndpoint = videoRenderer['navigationEndpoint']?['watchEndpoint'];
        if (navEndpoint != null) {
          plId = navEndpoint['playlistId'] as String?;
          prm = navEndpoint['params'] as String?;
        }
        
        list.add(YoutubeMusicVideo(
          videoId: videoId, 
          title: title, 
          artist: artist.trim(), 
          thumbnailUrl: thumbnailUrl, 
          duration: duration, 
          playlistId: plId, 
          params: prm
        ));
        addedVideoIds.add(videoId);
      }

      for (final item in topLevelContents) {
        if (item['playlistPanelVideoRenderer'] != null) {
          parseAndAddVideo(item['playlistPanelVideoRenderer']);
        } else if (item['automixPreviewVideoRenderer'] != null) {
          final automixContents = item['automixPreviewVideoRenderer']?['content']?['playlistPanelRenderer']?['contents'] as List?;
          if (automixContents != null) {
            for (final automixItem in automixContents) {
              if (automixItem['playlistPanelVideoRenderer'] != null) {
                parseAndAddVideo(automixItem['playlistPanelVideoRenderer']);
              }
            }
          }
        }
      }

      _logger.info('_parseNextResponse: Successfully parsed ${list.length} videos in total.');
    } catch (e, stackTrace) {
      _logger.severe('Error parsing /next response: $e', e, stackTrace);
    }
    return (videos: list, continuationToken: continuationToken);
  }

  // --- Get Streaming URL (using YoutubeDLService or Proxy for Web, adapted from old YouTubeService) ---
  Future<String?> getStreamingUrl(String videoId) async {
    try {
      if (!await _checkConnectivityStatus()) {
        _logger.warning('No internet connectivity for streaming URL');
        return null;
      }

      // For non-web platforms, use YoutubeDLService
      _logger.info('Getting streaming URL for video ID: $videoId using YoutubeDLService (non-web)');
      final youtubeDLService = YoutubeDLService();
      String? url;
      try {
        url = await youtubeDLService.getStreamUrl(videoId);
      } catch (e) {
        _logger.warning('Error using YoutubeDLService: $e');
      }
      if (url == null) {
        _logger.warning('Could not get streaming URL for video ID: $videoId from YoutubeDLService');
        return null;
      }
      // URL validation and fixing logic from original implementation
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        _logger.warning('Invalid URL format from YoutubeDLService: $url');
        if (url.startsWith('//')) {
          url = 'https:$url';
          _logger.info('Fixed URL by adding https: scheme');
        } else if (url.startsWith('/')) {
          // This case might be problematic if _musicApiDomain is not the correct host for the stream
          url = 'https://$_musicApiDomain$url'; 
          _logger.info('Fixed URL by adding https://$_musicApiDomain scheme');
        } else {
          url = 'https://$url';
          _logger.info('Fixed URL by adding https:// scheme');
        }
      }
      try {
        final uri = Uri.parse(url);
        if (uri.scheme.isEmpty || (!uri.scheme.startsWith('http'))) {
          throw Exception('Invalid URL scheme after fix: ${uri.scheme}');
        }
        _logger.info('Validated stream URL: scheme=${uri.scheme}, host=${uri.host}');
      } catch (e) {
        _logger.severe('Stream URL validation failed after potential fix: $e. Original URL from service: $url');
        return null;
      }
      _logger.info('Successfully obtained and validated streaming URL for video ID: $videoId (non-web)');
      return url;
    } catch (e, stackTrace) {
      _logger.severe('Error in getStreamingUrl (YouTubeApiService): $e', e, stackTrace);
      return null;
    }
  }

  // --- MediaItem Conversion (from former YouTubeService) ---
  MediaItem youtubeVideoToMediaItem(YoutubeMusicVideo video) {
    return MediaItem(
      id: video.videoId,
      title: video.title,
      artist: video.artist,
      duration: _parseMediaItemDuration(video.duration),
      artUri: Uri.tryParse(video.thumbnailUrl),
      extras: {
        'url': video.videoId, 
        'source': 'youtube_music',
        'videoId': video.videoId,
        if (video.playlistId != null) 'playlistId': video.playlistId,
        if (video.params != null) 'params': video.params,
      },
    );
  }

  Duration? _parseMediaItemDuration(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return null;
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      } else if (parts.length == 3) {
        return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]), seconds: int.parse(parts[2]));
      } else if (parts.length == 1) {
        return Duration(seconds: int.parse(parts[0]));
      }
    } catch (e) {
      _logger.warning('Error parsing MediaItem duration "$durationStr": $e');
    }
    return null;
  }
  
  static int _min(int a, int b) => a < b ? a : b;

  // --- Cache Keys ---
  static String _upNextCacheKey(String videoId) => 'up_next_data_for_$videoId';

  // --- "Up Next" (Similar Songs) Cache Handling ---
  Future<({List<YoutubeMusicVideo> videos, String? continuationToken})?> getUpNextDataFromCache(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedDataJson = prefs.getString(_upNextCacheKey(videoId));

      if (cachedDataJson != null) {
        final Map<String, dynamic> cachedData = json.decode(cachedDataJson);
        final List<dynamic> videosJson = cachedData['videos'] as List<dynamic>;
        final List<YoutubeMusicVideo> videos = videosJson
            .map((jsonItem) => YoutubeMusicVideo.fromJson(jsonItem as Map<String, dynamic>))
            .toList();
        final String? continuationToken = cachedData['continuationToken'] as String?;
        _logger.info('Loaded "Up Next" data from cache for videoId: $videoId. Found ${videos.length} items.');
        return (videos: videos, continuationToken: continuationToken);
      }
    } catch (e, stackTrace) {
      _logger.severe('Error loading "Up Next" data from cache for videoId: $videoId. Error: $e', e, stackTrace);
    }
    _logger.info('No "Up Next" data in cache for videoId: $videoId.');
    return null;
  }

  Future<void> saveUpNextDataToCache(String videoId, List<YoutubeMusicVideo> videos, String? continuationToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> dataToCache = {
        'videos': videos.map((v) => v.toJson()).toList(),
        'continuationToken': continuationToken,
      };
      final String dataToCacheJson = json.encode(dataToCache);
      await prefs.setString(_upNextCacheKey(videoId), dataToCacheJson);
      _logger.info('Saved "Up Next" data to cache for videoId: $videoId. Stored ${videos.length} items.');
    } catch (e, stackTrace) {
      _logger.severe('Error saving "Up Next" data to cache for videoId: $videoId. Error: $e', e, stackTrace);
    }
  }

  Future<void> clearUpNextDataFromCache(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_upNextCacheKey(videoId));
      _logger.info('Cleared "Up Next" data from cache for videoId: $videoId.');
    } catch (e, stackTrace) {
      _logger.severe('Error clearing "Up Next" data from cache for videoId: $videoId. Error: $e', e, stackTrace);
    }
  }

  void dispose() {
    _connectivityController.close();
  }
}
