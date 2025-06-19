import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/widgets/search/search_filters.dart';
import 'package:asteroid/api/youtube_api_service.dart'; // Updated import
import 'package:asteroid/utils/ui_utils.dart';
import 'package:asteroid/audio_handler.dart';
import 'package:logging/logging.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static final Logger _logger = Logger('SearchScreen');
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  // final _debouncer = _Debouncer(milliseconds: 500); // Removed debouncer instance

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    if (!searchProvider.isLoadingMore &&
        searchProvider.continuationToken != null) {
      searchProvider.setLoadingMore(true);
      try {
        final results = await YouTubeApiService().searchMusicContinuation(searchProvider.continuationToken!);
        if (!mounted) return;
        searchProvider.appendResults(results, continuation: YouTubeApiService.lastSearchContinuationToken);
      } catch (e) {
        if (!mounted) return;
        UIUtils.showError(
          context,
          'Failed to load more results. Please try again.',
        );
      } finally {
        if (mounted) {
          searchProvider.setLoadingMore(false);
        }
      }
    }
  }

  bool _isSearching = false;

  Future<void> _performSearch(String query) async {
    _logger.info('[SearchScreen _performSearch] Received query: "$query"');
    
    if (query.isEmpty) {
      final searchProvider = Provider.of<SearchProvider>(context, listen: false);
      if (searchProvider.query.isNotEmpty || searchProvider.results.isNotEmpty) {
        searchProvider.setQuery('');
        searchProvider.setResults([]);
      }
      return;
    }

    if (_isSearching) {
      _logger.info('Search already in progress for "${Provider.of<SearchProvider>(context, listen: false).query}". Debounced call for "$query" ignored.');
      return;
    }

    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    searchProvider.setQuery(query);

    // final cachedResults = searchProvider.getCachedResults(query); // Removed cache check
    // if (cachedResults != null) {
    //   _logger.info('Serving search results for "$query" from cache.');
    //   searchProvider.setResults(cachedResults);
    //   return;
    // }

    _logger.info('Performing live search for "$query".');
    setState(() => _isSearching = true);
    searchProvider.setLoading(true);
    
    try {      
      final results = await YouTubeApiService().searchMusic(query);
      if (!mounted) return;
      searchProvider.setResults(results, continuation: YouTubeApiService.lastSearchContinuationToken);
    } catch (e) {
      if (!mounted) return;
      _logger.severe('Search failed for "$query": $e');
      UIUtils.showError(context, 'Search failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
        searchProvider.setLoading(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Consumer<SearchProvider>(
              builder: (context, searchProvider, child) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Focus(
                        onFocusChange: (hasFocus) {
                          if (!hasFocus) {
                            FocusScope.of(context).unfocus();
                          }
                        },
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            FocusScope.of(context).unfocus();
                            _performSearch(value); // Call _performSearch directly
                          },
                          decoration: InputDecoration(
                          hintText: 'Search songs, artists, or albums',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    // This will trigger onChanged with empty value,
                                    // which will then call _performSearch with empty query
                                    // and clear results via the debouncer.
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                          // onChanged: (value) { // Removed onChanged handler
                          //   _logger.info('[SearchScreen TextField onChanged] Value: "$value"');
                          //   _debouncer.run(() => _performSearch(value));
                          // },
                        ),
                      ),
                    ),
                    if (searchProvider.query.isNotEmpty) ...[
                      const SearchFilters(),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _performSearch(searchProvider.query),
                        child: searchProvider.isLoading
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Searching...'),
                                  ],
                                ),
                              )
                            : searchProvider.results.isEmpty
                                ? Center(
                                    child: Text(
                                      searchProvider.query.isEmpty
                                          ? 'Search for music'
                                          : 'No results found',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () {
                                      FocusScope.of(context).unfocus();
                                    },
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                      padding: const EdgeInsets.only(bottom: 80),
                                      itemCount: searchProvider.results.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == searchProvider.results.length) {
                                        if (searchProvider.isLoadingMore) {
                                          return const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(),
                                                  SizedBox(height: 8),
                                                  Text('Loading more...'),
                                                ],
                                              ),
                                            ),
                                          );
                                        }
                                        return searchProvider.continuationToken != null
                                            ? const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Text('Pull up to load more'),
                                                ),
                                              )
                                            : const SizedBox.shrink();
                                      }

                                      final result = searchProvider.results[index];
                                      return Consumer<AudioHandler>(
                                        builder: (context, audioHandler, child) {
                                          final myAudioHandler = audioHandler as MyAudioHandler;
                                          return StreamBuilder<MediaItem?>(
                                            stream: myAudioHandler.mediaItem,
                                            builder: (context, mediaItemSnapshot) {
                                              return StreamBuilder<PlaybackState>(
                                                stream: myAudioHandler.playbackState,
                                                builder: (context, playbackStateSnapshot) {
                                                  final currentMediaItem = mediaItemSnapshot.data;
                                                  final playbackState = playbackStateSnapshot.data;
                                                  bool isCurrentlyPlayingThisSong = false;
                                                  IconData iconData = Icons.play_arrow;

                                                  if (currentMediaItem != null &&
                                                      (currentMediaItem.extras?['videoId'] == result.videoId || currentMediaItem.id == result.videoId) &&
                                                      playbackState != null &&
                                                      playbackState.playing) {
                                                    isCurrentlyPlayingThisSong = true;
                                                    iconData = Icons.pause;
                                                  }

                                                  VoidCallback? onPressedAction;
                                                  if (isCurrentlyPlayingThisSong) {
                                                    onPressedAction = () => myAudioHandler.pause();
                                                  } else {
                                                    onPressedAction = () async {
                                                      try {
                                                        final mediaItemToPlay = MediaItem(
                                                          id: result.videoId,
                                                          title: result.title,
                                                          artist: result.artist,
                                                          artUri: Uri.parse(result.thumbnailUrl),
                                                          extras: {
                                                            'url': result.videoId,
                                                            'videoId': result.videoId,
                                                            'duration': result.duration,
                                                            'playlistId': result.playlistId,
                                                            'params': result.params,
                                                            'trackingParams': result.trackingParams,
                                                          },
                                                        );
                                                        if (currentMediaItem != null &&
                                                            (currentMediaItem.extras?['videoId'] == result.videoId || currentMediaItem.id == result.videoId) &&
                                                            playbackState != null &&
                                                            !playbackState.playing) {
                                                          await myAudioHandler.play();
                                                        } else {
                                                          await myAudioHandler.playMediaItem(mediaItemToPlay, isFromSearch: true);
                                                        }
                                                      } catch (e) {
                                                        if (mounted) UIUtils.showError(context, e.toString());
                                                      }
                                                    };
                                                  }

                                                  return ListTile(
                                                    leading: ClipRRect(
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: Image.network(
                                                        result.thumbnailUrl,
                                                        width: 48,
                                                        height: 48,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                          return const Icon(Icons.broken_image, size: 48); // Placeholder for failed images
                                                        },
                                                      ),
                                                    ),
                                                    title: Text(
                                                      result.title,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    subtitle: Text(
                                                      result.artist,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    trailing: result.isArtist || result.isAlbum || result.isPlaylist
                                                        ? Icon(result.isPlaylist ? Icons.playlist_play : Icons.chevron_right)
                                                        : IconButton(
                                                            icon: Icon(iconData),
                                                            onPressed: onPressedAction,
                                                          ),
                                                    onTap: () async {
                                                      if (result.isArtist || result.isAlbum) {
                                                        // TODO: Navigate to artist/album page
                                                        _logger.info('Tapped on artist/album: ${result.title}');
                                                      } else if (result.isPlaylist) {
                                                        // TODO: Navigate to playlist page or start playlist playback
                                                        _logger.info('Tapped on playlist: ${result.title} (ID: ${result.playlistId})');
                                                        // For now, let's try to play the first song of the playlist if we had that logic
                                                        // Or navigate to a playlist detail screen
                                                      } else {
                                                        if (onPressedAction != null) {
                                                          onPressedAction();
                                                        }
                                                      }
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
    );
  }
}

// class _Debouncer { // Removed _Debouncer class
//   final int milliseconds;
//   Timer? _timer;
//
//   _Debouncer({required this.milliseconds});
//
//   void run(VoidCallback action) {
//     _timer?.cancel();
//     _timer = Timer(Duration(milliseconds: milliseconds), action);
//   }
// }
