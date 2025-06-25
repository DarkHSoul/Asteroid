import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/api/youtube_api_service.dart';
import 'package:asteroid/utils/ui_utils.dart';
import 'package:asteroid/audio_handler.dart';

class SearchResultsView extends StatelessWidget {
  final ScrollController scrollController;

  const SearchResultsView({
    super.key,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final searchProvider = Provider.of<SearchProvider>(context);
    final audioHandler = Provider.of<MyAudioHandler>(context);

    if (searchProvider.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...'),
          ],
        ),
      );
    }

    if (searchProvider.results.isEmpty) {
      return Center(
        child: Text(
          searchProvider.query.isEmpty
              ? 'Search for music'
              : 'No results found',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
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
        return StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, mediaItemSnapshot) {
            return StreamBuilder<PlaybackState>(
              stream: audioHandler.playbackState,
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
                  onPressedAction = () => audioHandler.pause();
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
                        await audioHandler.play();
                      } else {
                        await audioHandler.playMediaItem(mediaItemToPlay, isFromSearch: true);
                      }
                    } catch (e) {
                      UIUtils.showError(context, e.toString());
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
                        return const Icon(Icons.broken_image, size: 48);
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
                    } else if (result.isPlaylist) {
                      // TODO: Navigate to playlist page
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
  }
}
