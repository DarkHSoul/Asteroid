import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/library_provider.dart';
import 'package:asteroid/widgets/library/playlist_card.dart';
import 'package:asteroid/widgets/library/song_list_item.dart';

class PlaylistsSection extends StatelessWidget {
  final AudioHandler audioHandler;

  const PlaylistsSection({
    super.key,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        final playlists = library.playlists;

        if (playlists.isEmpty) {
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: 64,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No playlists yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create your first playlist',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  onPressed: () => _showCreatePlaylistDialog(context),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          );
        }

        return Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final name = playlists.keys.elementAt(index);
                final songs = playlists[name]!;

                return PlaylistCard(
                  name: name,
                  songs: songs,
                  onTap: () => _showPlaylistDetails(context, name, songs),
                  onDelete: () => _showDeletePlaylistDialog(context, name),
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () => _showCreatePlaylistDialog(context),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Playlist'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Provider.of<LibraryProvider>(context, listen: false)
                    .createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<LibraryProvider>(context, listen: false)
                  .deletePlaylist(name);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistDetails(BuildContext context, String name, List<MediaItem> songs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill),
                      iconSize: 48,
                      onPressed: songs.isEmpty ? null : () async {
                        // Play all songs in playlist
                        if (songs.isNotEmpty) {
                          final firstSong = songs.first.copyWith(
                            id: songs.first.extras?['url'] ?? songs.first.id,
                          );
                          await audioHandler.playMediaItem(firstSong);
                          for (var i = 1; i < songs.length; i++) {
                            await audioHandler.addQueueItem(songs[i]);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: audioHandler.mediaItem,
                  builder: (context, snapshot) {
                    final currentSong = snapshot.data;
                    
                    return StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, playbackSnapshot) {
                        final isPlaying = playbackSnapshot.data?.playing ?? false;

                        if (songs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 64,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No songs in playlist',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).disabledColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: songs.length,
                          onReorder: (oldIndex, newIndex) {
                            final provider = Provider.of<LibraryProvider>(context, listen: false);
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            final item = songs[oldIndex];
                            provider.removeFromPlaylist(name, item);
                            provider.addToPlaylist(name, item);
                          },
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final isCurrentSong = currentSong?.id == song.id;

                            return SongListItem(
                              key: ValueKey(song.id),
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
                              onRemove: () {
                                Provider.of<LibraryProvider>(context, listen: false)
                                    .removeFromPlaylist(name, song);
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
