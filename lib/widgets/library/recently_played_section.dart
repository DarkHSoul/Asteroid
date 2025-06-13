import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/library_provider.dart';
import 'package:asteroid/widgets/library/song_list_item.dart';

class RecentlyPlayedSection extends StatelessWidget {
  final AudioHandler audioHandler;

  const RecentlyPlayedSection({
    super.key,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        final recentSongs = library.recentlyPlayed;

        if (recentSongs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'No recently played songs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
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
                  itemCount: recentSongs.length,
                  itemBuilder: (context, index) {
                    final song = recentSongs[index];
                    final isCurrentSong = currentSong?.id == song.id;

                    return SongListItem(
                      song: song,
                      isPlaying: isCurrentSong && isPlaying,
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
