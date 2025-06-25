import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/queue_provider.dart';
import 'package:asteroid/audio_handler.dart';

class PlayerControls extends StatelessWidget {
  final double size;
  final bool showLabels;
  final VoidCallback? onQueueTap;

  const PlayerControls({
    super.key,
    this.size = 1.0,
    this.showLabels = true,
    this.onQueueTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MyAudioHandler>(
      builder: (context, audioHandler, child) {
        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, snapshot) {
            final playbackState = snapshot.data ?? PlaybackState();
            final playing = playbackState.playing;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar
                StreamBuilder<Duration>(
                  stream: AudioService.position,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    return StreamBuilder<MediaItem?>(
                      stream: audioHandler.mediaItem,
                      builder: (context, snapshot) {
                        final duration = snapshot.data?.duration ?? Duration.zero;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: Theme.of(context).colorScheme.primary, // Use colorScheme.primary
                                inactiveTrackColor: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.3), // Use onSurface for inactive
                                thumbColor: Theme.of(context).colorScheme.primary, // Use colorScheme.primary
                                overlayColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.3), // Use colorScheme.primary
                              ),
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                                max: duration.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  audioHandler.seek(
                                    Duration(milliseconds: value.round()),
                                  );
                                },
                              ),
                            ),
                            if (showLabels)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 8),

                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Consumer<QueueProvider>(
                      builder: (context, queueProvider, child) {
                        return IconButton(
                          icon: Icon(
                            queueProvider.shuffleMode
                                ? Icons.shuffle
                                : Icons.shuffle_outlined,
                            color: queueProvider.shuffleMode
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                          iconSize: 24 * size,
                          onPressed: queueProvider.toggleShuffle,
                        );
                      },
                    ),
                    Consumer<QueueProvider>(
                      builder: (context, queueProvider, child) {
                        return IconButton(
                          icon: const Icon(Icons.skip_previous),
                          iconSize: 32 * size,
                          onPressed: queueProvider.skipToPrevious,
                        );
                      },
                    ),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).primaryColor,
                      ),
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          iconSize: 48 * size,
                          onPressed: playing
                              ? audioHandler.pause
                              : audioHandler.play,
                        ),
                      ),
                    ),
                    Consumer<QueueProvider>(
                      builder: (context, queueProvider, child) {
                        return IconButton(
                          icon: const Icon(Icons.skip_next),
                          iconSize: 32 * size,
                          onPressed: queueProvider.skipToNext,
                        );
                      },
                    ),
                    Consumer<QueueProvider>(
                      builder: (context, queueProvider, child) {
                        return IconButton(
                          icon: Icon(
                            queueProvider.repeatMode == RepeatMode.off
                                ? Icons.repeat_outlined
                                : queueProvider.repeatMode == RepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                            color: queueProvider.repeatMode != RepeatMode.off
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                          iconSize: 24 * size,
                          onPressed: queueProvider.cycleRepeatMode,
                        );
                      },
                    ),
                  ],
                ),

                if (showLabels) ...[
                  const SizedBox(height: 16),
                  // Queue button
                  TextButton.icon(
                    onPressed: onQueueTap,
                    icon: const Icon(Icons.queue_music),
                    label: const Text('Queue'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
