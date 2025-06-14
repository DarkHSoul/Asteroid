import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/library_provider.dart';
import 'package:asteroid/widgets/library/song_list_item.dart';

class FavoritesSection extends StatelessWidget {
  final AudioHandler audioHandler;

  const FavoritesSection({
    super.key,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        final favorites = library.favorites;

        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'No favorite songs yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the heart icon on any song to add it to favorites',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final currentSong = snapshot.data;
            
            return StreamBuilder<PlaybackState>(
              stream: audioHandler.playbackState,
              builder: (context, playbackSnapshot) {
                final isPlaying = playbackSnapshot.data?.playing ?? false;

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final song = favorites[index];
                    final isCurrentSong = currentSong?.id == song.id;

                    return Dismissible(
                      key: Key(song.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20.0),
                        color: Colors.red,
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (direction) {
                        library.toggleFavorite(song);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Removed from favorites'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => library.toggleFavorite(song),
                            ),
                          ),
                        );
                      },
                      child: SongListItem(
                        song: song,
                        isPlaying: isCurrentSong && isPlaying,
                        showFavorite: false, // Hide favorite button since we're in favorites
                        onPlay: () async {
                          if (isCurrentSong) {
                            if (isPlaying) {
                              await audioHandler.pause();
                            } else {
                              await audioHandler.play();
                            }
                          } else {
                            final mediaItem = song.copyWith(
                              id: song.extras?['url'] ?? song.id,
                            );
                            await audioHandler.playMediaItem(mediaItem);
                          }
                        },
                      ),
                    );
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
