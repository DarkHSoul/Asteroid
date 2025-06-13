import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/widgets/search/search_filters.dart';
import 'package:asteroid/widgets/search/related_songs.dart';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/widgets/app_drawer.dart';
import 'package:asteroid/widgets/player_bar.dart';
import 'package:asteroid/utils/ui_utils.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _debouncer = _Debouncer(milliseconds: 500);

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
        final api = YoutubeMusicAPI();
        final results = await api.searchMore(searchProvider.continuationToken!);
        if (!mounted) return;
        searchProvider.appendResults(results.items, continuation: results.continuation);
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
  Timer? _searchDebouncer;

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    if (_isSearching) {
      _searchDebouncer?.cancel();
      _searchDebouncer = Timer(const Duration(milliseconds: 500), () => _performSearch(query));
      return;
    }

    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    searchProvider.setQuery(query);

    // Check cache first
    final cachedResults = searchProvider.getCachedResults(query);
    if (cachedResults != null) {
      searchProvider.setResults(cachedResults);
      return;
    }

    setState(() => _isSearching = true);
    searchProvider.setLoading(true);
    
    try {
      final api = YoutubeMusicAPI();
      final results = await api.search(query);
      if (!mounted) return;
      searchProvider.setResults(results.items, continuation: results.continuation);
    } catch (e) {
      if (!mounted) return;
      UIUtils.showError(context, 'Search failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
        searchProvider.setLoading(false);
      }
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
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
                            // Hide keyboard when focus is lost
                            FocusScope.of(context).unfocus();
                          }
                        },
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            // Hide keyboard when search is submitted
                            FocusScope.of(context).unfocus();
                            _performSearch(value);
                          },
                          decoration: InputDecoration(
                          hintText: 'Search songs, artists, or albums',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    searchProvider.setQuery('');
                                    searchProvider.setResults([]);
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                          onChanged: (value) {
                            _debouncer.run(() => _performSearch(value));
                          },
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
                                      // Hide keyboard when tapping outside of text field
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
                                          return ListTile(
                                            leading: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Image.network(
                                                result.thumbnail,
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
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
                                            trailing: result.isArtist || result.isAlbum
                                                ? const Icon(Icons.chevron_right)
                                                : IconButton(
                                                    icon: const Icon(Icons.play_arrow),
                                                    onPressed: () async {
                                                      try {
                                                        final mediaItem = MediaItem(
                                                          id: result.videoId,
                                                          title: result.title,
                                                          artist: result.artist,
                                                          artUri: Uri.parse(result.thumbnail),
                                                          extras: {
                                                            'url': result.videoId,
                                                            'duration': result.duration,
                                                          },
                                                        );
                                                        await audioHandler.playMediaItem(mediaItem);

                                                        // Load related songs
                                                        try {
                                                          final api = YoutubeMusicAPI();
                                                          final related = await api.getRelatedSongs(result.videoId);
                                                          searchProvider.updateRelatedSongs(related);
                                                        } catch (e) {
                                                          debugPrint('Error loading related songs: $e');
                                                        }
                                                      } catch (e) {
                                                        UIUtils.showError(context, e.toString());
                                                      }
                                                    },
                                                  ),
                                            onTap: () async {
                                              if (result.isArtist || result.isAlbum) {
                                                // TODO: Navigate to artist/album page
                                              } else {
                                                try {
                                                  final mediaItem = MediaItem(
                                                    id: result.videoId,
                                                    title: result.title,
                                                    artist: result.artist,
                                                    artUri: Uri.parse(result.thumbnail),
                                                    extras: {
                                                      'url': result.videoId,
                                                      'duration': result.duration,
                                                    },
                                                  );
                                                  await audioHandler.playMediaItem(mediaItem);

                                                  // Load related songs
                                                  try {
                                                    final api = YoutubeMusicAPI();
                                                    final related = await api.getRelatedSongs(result.videoId);
                                                    searchProvider.updateRelatedSongs(related);
                                                  } catch (e) {
                                                    debugPrint('Error loading related songs: $e');
                                                  }
                                                } catch (e) {
                                                  UIUtils.showError(context, e.toString());
                                                }
                                              }
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                      ),
                    ),
                    if (searchProvider.relatedSongs.isNotEmpty)
                      Consumer<AudioHandler>(
                        builder: (context, audioHandler, child) {
                          return RelatedSongs(audioHandler: audioHandler);
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }
}

class _Debouncer {
  final int milliseconds;
  Timer? _timer;

  _Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
