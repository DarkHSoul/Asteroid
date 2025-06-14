import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/api/youtube_music_api.dart';

class RelatedSongs extends StatelessWidget {
  final AudioHandler audioHandler;

  const RelatedSongs({
    super.key,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, searchProvider, child) {
        final relatedSongs = searchProvider.relatedSongs;

        if (relatedSongs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Related Songs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: relatedSongs.length,
              itemBuilder: (context, index) {
                final song = relatedSongs[index];
                return _RelatedSongTile(
                  song: song,
                  audioHandler: audioHandler,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RelatedSongTile extends StatelessWidget {
  final YoutubeMusicVideo song;
  final AudioHandler audioHandler;

  const _RelatedSongTile({
    required this.song,
    required this.audioHandler,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        final currentSong = snapshot.data;
        final isPlaying = currentSong?.id == song.videoId;

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              song.thumbnail,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 48,
                height: 48,
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                child: const Icon(Icons.music_note),
              ),
            ),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isPlaying ? FontWeight.bold : null,
              color: isPlaying ? Theme.of(context).primaryColor : null,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: StreamBuilder<PlaybackState>(
            stream: audioHandler.playbackState,
            builder: (context, snapshot) {
              final playbackState = snapshot.data;
              final playing = playbackState?.playing ?? false;

              return IconButton(
                icon: Icon(
                  isPlaying && playing ? Icons.pause : Icons.play_arrow,
                  color: isPlaying ? Theme.of(context).primaryColor : null,
                ),
                onPressed: () async {
                  if (isPlaying) {
                    if (playing) {
                      await audioHandler.pause();
                    } else {
                      await audioHandler.play();
                    }
                  } else {
                    final mediaItem = MediaItem(
                      id: song.videoId,
                      title: song.title,
                      artist: song.artist,
                      artUri: Uri.parse(song.thumbnail),
                      extras: {
                        'url': song.videoId,
                        'duration': song.duration,
                      },
                    );
                    await audioHandler.playMediaItem(mediaItem);
                  }
                },
              );
            },
          ),
          onTap: () async {
            if (!isPlaying) {
              final mediaItem = MediaItem(
                id: song.videoId,
                title: song.title,
                artist: song.artist,
                artUri: Uri.parse(song.thumbnail),
                extras: {
                  'url': song.videoId,
                  'duration': song.duration,
                },
              );
              await audioHandler.playMediaItem(mediaItem);
            }
          },
        );
      },
    );
  }
}
