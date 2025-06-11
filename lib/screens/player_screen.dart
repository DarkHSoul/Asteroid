import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);
    // Safely cast to dynamic to access nextSongsStream if available
    Stream<List<MediaItem>>? nextSongsStream;
    try {
      nextSongsStream = (audioHandler as dynamic).nextSongsStream as Stream<List<MediaItem>>?;
    } catch (_) {
      nextSongsStream = null;
    }

    return StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, snapshot) {
          final mediaItem = snapshot.data;
          if (mediaItem == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('No song selected')),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(mediaItem.title),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mediaItem.artUri != null) Image.network(mediaItem.artUri.toString()),
                    const SizedBox(height: 20),
                    Text(mediaItem.title, style: Theme.of(context).textTheme.headlineSmall),
                    Text(mediaItem.artist ?? '', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, snapshot) {
                        final playbackState = snapshot.data;
                        final position = playbackState?.updatePosition ?? Duration.zero;
                        // Get duration from the player directly if mediaItem.duration is null
                        Duration duration = mediaItem.duration ?? Duration.zero;
                        
                        // Format durations for display
                        String formatDuration(Duration d) {
                          String twoDigits(int n) => n.toString().padLeft(2, '0');
                          String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
                          String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
                          return "${d.inHours > 0 ? '${d.inHours}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
                        }
                        
                        return Column(
                          children: [
                            Slider(
                              value: position.inSeconds.toDouble().clamp(0, duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1),
                              min: 0,
                              max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1,
                              onChanged: (value) {
                                audioHandler.seek(Duration(seconds: value.toInt()));
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(formatDuration(position)),
                                Text(formatDuration(duration)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    StreamBuilder<PlaybackState>(
                        stream: audioHandler.playbackState,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data?.playing ?? false;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                onPressed: audioHandler.skipToPrevious,
                                iconSize: 48,
                              ),
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                onPressed: () {
                                  if (isPlaying) {
                                    audioHandler.pause();
                                  } else {
                                    audioHandler.play();
                                  }
                                },
                                iconSize: 64,
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                onPressed: audioHandler.skipToNext,
                                iconSize: 48,
                              ),
                            ],
                          );
                        }),
                    const SizedBox(height: 24),
                    if (nextSongsStream != null)
                      StreamBuilder<List<MediaItem>>(
                        stream: nextSongsStream,
                        builder: (context, snapshot) {
                          final nextSongs = snapshot.data ?? [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Up Next:', style: TextStyle(fontWeight: FontWeight.bold)),
                              if (nextSongs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text('No next songs', style: TextStyle(color: Colors.grey)),
                                )
                              else
                                ...nextSongs.take(3).map((song) => Row(
                                      children: [
                                        if (song.artUri != null)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Image.network(
                                              song.artUri.toString(),
                                              width: 32,
                                              height: 32,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            song.title,
                                            style: Theme.of(context).textTheme.bodyMedium,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if ((song.artist ?? '').isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0),
                                            child: Text(
                                              song.artist!,
                                              style: Theme.of(context).textTheme.bodySmall,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    )),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        });
  }
} 