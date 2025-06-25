import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/widgets/search/search_filters.dart';
import 'package:asteroid/api/youtube_api_service.dart';
import 'package:asteroid/utils/ui_utils.dart';
import 'package:asteroid/audio_handler.dart';
import 'package:asteroid/widgets/search/search_bar.dart';
import 'package:asteroid/widgets/search/search_results_view.dart';
import 'package:logging/logging.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static final Logger _logger = Logger('SearchScreen');
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  Future<void> _performSearch(String query) async {
    _logger.info('[SearchScreen _performSearch] Received query: "$query"');

    final searchProvider = Provider.of<SearchProvider>(context, listen: false);

    if (query.isEmpty) {
      if (searchProvider.query.isNotEmpty || searchProvider.results.isNotEmpty) {
        searchProvider.setQuery('');
        searchProvider.setResults([]);
      }
      return;
    }

    if (searchProvider.isLoading) {
      _logger.info('Search already in progress for "${searchProvider.query}". Call for "$query" ignored.');
      return;
    }

    searchProvider.setQuery(query);
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
        searchProvider.setLoading(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              CustomSearchBar(onSearch: _performSearch),
              Consumer<SearchProvider>(
                builder: (context, searchProvider, child) {
                  if (searchProvider.query.isNotEmpty) {
                    return const SearchFilters();
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: RefreshIndicator(
                    onRefresh: () => _performSearch(
                      Provider.of<SearchProvider>(context, listen: false).query,
                    ),
                    child: SearchResultsView(
                      scrollController: _scrollController,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
