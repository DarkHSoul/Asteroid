import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class YoutubeMusicVideo {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String duration;
  final int? viewCount;
  String? trackingParams;

  YoutubeMusicVideo({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.viewCount,
    this.trackingParams,
  });
}

class YouTubeMusicApi {
  static final Logger _logger = Logger('YouTubeMusicApi');
  
  // Define proper base domains for different endpoints
  static const String _musicDomain = 'music.youtube.com';
  static const String _apiPath = '/youtubei/v1';
  static const String _searchEndpoint = '/search';
  
  // User agent for requests
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
  
  // API key for YouTube Music
  static const String _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  
  // Check network connectivity
  static Future<bool> isNetworkAvailable() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _logger.severe('Error checking network connectivity: $e');
      return false;
    }
  }
  
  // Search for music videos using POST request to music.youtube.com/youtubei/v1/search
  static Future<List<YoutubeMusicVideo>> search(String query) async {
    try {
      // Check network connectivity first
      if (!await isNetworkAvailable()) {
        _logger.warning('Network not available for search');
        return [];
      }
      
      // Construct the URL for POST request
      final url = Uri.https(_musicDomain, '$_apiPath$_searchEndpoint');
      
      // Create the request body
      final requestBody = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250602.03.00',
            'hl': 'en',
            'gl': 'US',
            'userAgent': _userAgent,
            'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
            'browserName': 'Chrome',
            'browserVersion': '137.0.0.0',
            'osName': 'Windows',
            'osVersion': '10.0',
            'platform': 'DESKTOP',
          },
          'user': {
            'lockedSafetyMode': false
          },
          'request': {
            'useSsl': true,
            'internalExperimentFlags': [],
            'consistencyTokenJars': []
          },
        },
        'query': query,
      };
      
      _logger.info('Sending search request to: $url');
      
      final response = await http.post(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Accept-Language': 'en-US,en;q=0.9',
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'Origin': 'https://$_musicDomain',
          'Referer': 'https://$_musicDomain/',
          'X-Youtube-Client-Name': '67',
          'X-Youtube-Client-Version': '1.20250602.03.00',
          'X-Origin': 'https://$_musicDomain',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        _logger.info('Received search response with status code 200');
        
        // Parse the response JSON
        final jsonResponse = json.decode(response.body);
        
        // Extract videos from the response
        final videos = _parseSearchResponse(jsonResponse);
        
        // Store the tracking parameters to use for player requests
        for (var video in videos) {
          if (jsonResponse['contents'] != null && 
              jsonResponse['trackingParams'] != null) {
            // Store the tracking params in the video for later use
            video.trackingParams = jsonResponse['trackingParams'];
          }
        }
        
        return videos;
      } else {
        _logger.warning('Search failed with status code: ${response.statusCode}');
        _logger.warning('Response body: ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error searching YouTube Music: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
    
    return [];
  }
  
  // Parse the search response to extract video information
  static List<YoutubeMusicVideo> _parseSearchResponse(Map<String, dynamic> response) {
    final List<YoutubeMusicVideo> videos = [];
    
    try {
      // Check if the contents section exists
      if (response['contents'] == null) {
        _logger.warning('Response missing contents section');
        return videos;
      }
      
      // Navigate to the section containing search results
      final tabbedResults = response['contents']['tabbedSearchResultsRenderer'];
      if (tabbedResults == null || tabbedResults['tabs'] == null) {
        _logger.warning('Response missing tabbedSearchResultsRenderer or tabs');
        return videos;
      }
      
      final tabs = tabbedResults['tabs'] as List;
      for (final tab in tabs) {
        if (tab['tabRenderer'] == null || tab['tabRenderer']['content'] == null) {
          continue;
        }
        
        final sectionListRenderer = tab['tabRenderer']['content']['sectionListRenderer'];
        if (sectionListRenderer == null || sectionListRenderer['contents'] == null) {
          continue;
        }
        
        final contents = sectionListRenderer['contents'] as List;
        for (final section in contents) {
          // Look for musicShelfRenderer (contains the music results)
          if (section['musicShelfRenderer'] != null && 
              section['musicShelfRenderer']['contents'] != null) {
            
            final items = section['musicShelfRenderer']['contents'] as List;
            for (final item in items) {
              if (item['musicResponsiveListItemRenderer'] != null) {
                final renderer = item['musicResponsiveListItemRenderer'];
                
                // Try to extract a YoutubeMusicVideo from this renderer
                try {
                  final video = _extractVideoFromRenderer(renderer);
                  if (video != null) {
                    videos.add(video);
                  }
                } catch (e) {
                  _logger.warning('Error extracting video from renderer: $e');
                }
              }
            }
          }
        }
      }
      
      _logger.info('Extracted ${videos.length} videos from search response');
    } catch (e, stackTrace) {
      _logger.severe('Error parsing search response: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
    
    return videos;
  }
  
  // Extract a single video from a renderer object
  static YoutubeMusicVideo? _extractVideoFromRenderer(Map<String, dynamic> renderer) {
    try {
      // Extract video ID
      String videoId = '';
      if (renderer['overlay'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer']['content'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer']['content']['musicPlayButtonRenderer'] != null) {
        
        final playButtonRenderer = renderer['overlay']['musicItemThumbnailOverlayRenderer']['content']['musicPlayButtonRenderer'];
        if (playButtonRenderer['playNavigationEndpoint'] != null &&
            playButtonRenderer['playNavigationEndpoint']['watchEndpoint'] != null) {
          
          videoId = playButtonRenderer['playNavigationEndpoint']['watchEndpoint']['videoId'] ?? '';
        }
      }
      
      if (videoId.isEmpty) {
        _logger.warning('Failed to extract videoId from renderer');
        return null;
      }
      
      // Extract title
      String title = '';
      if (renderer['flexColumns'] != null && renderer['flexColumns'].isNotEmpty) {
        final firstColumn = renderer['flexColumns'][0];
        if (firstColumn['musicResponsiveListItemFlexColumnRenderer'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'].isNotEmpty) {
          
          title = firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'][0]['text'] ?? '';
        }
      }
      
      if (title.isEmpty) {
        _logger.warning('Failed to extract title for video $videoId');
        return null;
      }
      
      // Extract artist and other metadata
      String artist = '';
      String duration = '';
      
      if (renderer['flexColumns'] != null && renderer['flexColumns'].length > 1) {
        final secondColumn = renderer['flexColumns'][1];
        if (secondColumn['musicResponsiveListItemFlexColumnRenderer'] != null &&
            secondColumn['musicResponsiveListItemFlexColumnRenderer']['text'] != null &&
            secondColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] != null) {
          
          final runs = secondColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List;
          
          // Typically artist is the first or second run
          if (runs.isNotEmpty) {
            artist = runs[0]['text'] ?? '';
            
            // Look for duration (usually formatted as MM:SS)
            for (final run in runs) {
              final text = run['text'] ?? '';
              if (text.contains(':') && RegExp(r'^\d+:\d+$').hasMatch(text)) {
                duration = text;
                break;
              }
            }
          }
        }
      }
      
      // Extract thumbnail URL
      String thumbnailUrl = '';
      if (renderer['thumbnail'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer']['thumbnail'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer']['thumbnail']['thumbnails'] != null) {
        
        final thumbnails = renderer['thumbnail']['musicThumbnailRenderer']['thumbnail']['thumbnails'] as List;
        if (thumbnails.isNotEmpty) {
          // Get the highest quality thumbnail
          thumbnailUrl = thumbnails.last['url'] ?? '';
        }
      }
      
      return YoutubeMusicVideo(
        videoId: videoId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        duration: duration,
      );
    } catch (e, stackTrace) {
      _logger.severe('Error extracting video from renderer: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    }
  }

  static Future<List<YoutubeMusicVideo>> fetchSimilarSongs(String videoId) async {
    print('fetchSimilarSongs called for videoId: $videoId');
    try {
      final url = Uri.https(_musicDomain, '$_apiPath/next');
      final requestBody = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250602.03.00',
            'hl': 'en',
            'gl': 'US',
            'userAgent': _userAgent,
            'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
            'browserName': 'Chrome',
            'browserVersion': '137.0.0.0',
            'osName': 'Windows',
            'osVersion': '10.0',
            'platform': 'DESKTOP',
          },
          'user': {
            'lockedSafetyMode': false
          },
          'request': {
            'useSsl': true,
            'internalExperimentFlags': [],
            'consistencyTokenJars': []
          },
        },
        'videoId': videoId,
      };
      final response = await http.post(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Accept-Language': 'en-US,en;q=0.9',
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'Origin': 'https://$_musicDomain',
          'Referer': 'https://$_musicDomain/',
          'X-Youtube-Client-Name': '67',
          'X-Youtube-Client-Version': '1.20250602.03.00',
          'X-Origin': 'https://$_musicDomain',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        print('YouTube /next response keys: \\${jsonResponse.keys}');
        // Try to find the related/queue section robustly
        final List<YoutubeMusicVideo> relatedVideos = [];
        // Print the structure for debugging
        void printKeys(dynamic obj, [String prefix = '']) {
          if (obj is Map) {
            for (final k in obj.keys) {
              print('$prefix$k');
              printKeys(obj[k], '$prefix  ');
            }
          } else if (obj is List) {
            for (int i = 0; i < obj.length; i++) {
              printKeys(obj[i], '$prefix[$i]');
            }
          }
        }
        print('--- YouTube /next response structure ---');
        printKeys(jsonResponse);
        print('--- End structure ---');
        // Try to find the "Up next"/queue section
        final contents = jsonResponse['contents'];
        if (contents != null) {
          // Try to find the musicQueueRenderer or playlistPanelRenderer
          final queueCandidates = [
            contents['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs'],
            contents['singleColumnMusicWatchNextResultsRenderer']?['sectionListRenderer']?['contents'],
          ];
          for (final candidate in queueCandidates) {
            if (candidate is List) {
              for (final tab in candidate) {
                final tabRenderer = tab['tabRenderer'] ?? tab['musicQueueRenderer'] ?? tab['sectionListRenderer'];
                if (tabRenderer != null) {
                  // Try to find playlistPanelRenderer
                  final sectionList = tabRenderer['content']?['sectionListRenderer'] ?? tabRenderer['sectionListRenderer'];
                  if (sectionList != null && sectionList['contents'] != null) {
                    final sections = sectionList['contents'] as List;
                    for (final section in sections) {
                      final musicQueue = section['musicQueueRenderer'];
                      if (musicQueue != null && musicQueue['content'] != null) {
                        final playlistPanel = musicQueue['content']['playlistPanelRenderer'];
                        if (playlistPanel != null && playlistPanel['contents'] != null) {
                          final queueItems = playlistPanel['contents'] as List;
                          for (final item in queueItems) {
                            final panelVideoRenderer = item['playlistPanelVideoRenderer'];
                            if (panelVideoRenderer != null) {
                              final videoId = panelVideoRenderer['videoId'] ?? '';
                              final titleRuns = panelVideoRenderer['title']?['runs'] as List?;
                              final title = (titleRuns != null && titleRuns.isNotEmpty) ? titleRuns[0]['text'] ?? '' : '';
                              final artistRuns = panelVideoRenderer['longBylineText']?['runs'] as List?;
                              final artist = (artistRuns != null && artistRuns.isNotEmpty) ? artistRuns[0]['text'] ?? '' : '';
                              final thumbnailList = panelVideoRenderer['thumbnail']?['thumbnails'] as List?;
                              final thumbnailUrl = (thumbnailList != null && thumbnailList.isNotEmpty) ? thumbnailList.last['url'] ?? '' : '';
                              final lengthText = panelVideoRenderer['lengthText']?['simpleText'] ?? '';
                              if (videoId.isNotEmpty && title.isNotEmpty) {
                                relatedVideos.add(YoutubeMusicVideo(
                                  videoId: videoId,
                                  title: title,
                                  artist: artist,
                                  thumbnailUrl: thumbnailUrl,
                                  duration: lengthText,
                                ));
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        print('Related videos parsed: \\${relatedVideos.length}');
        return relatedVideos;
      }
    } catch (e, stackTrace) {
      print('Error fetching similar songs: \\${e.toString()}');
      print('Stack trace: \\${stackTrace.toString()}');
    }
    return [];
  }
} 