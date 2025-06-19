import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/queue_provider.dart';
import 'package:asteroid/providers/up_next_provider.dart';
import 'package:asteroid/audio_handler.dart';

class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key});

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final upNextProvider = context.read<UpNextNotifier>();
      if (upNextProvider.canLoadMore && !upNextProvider.isLoadingMore) {
        upNextProvider.loadMoreUpNextItems();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Queue header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      'Queue',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Consumer<QueueProvider>(
                      builder: (context, queueProvider, child) {
                        return Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                queueProvider.shuffleMode
                                    ? Icons.shuffle
                                    : Icons.shuffle_outlined,
                                color: queueProvider.shuffleMode
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                              onPressed: queueProvider.toggleShuffle,
                            ),
                            IconButton(
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
                              onPressed: queueProvider.cycleRepeatMode,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Queue list
              Expanded(
                child: Consumer<UpNextNotifier>(
                  builder: (context, upNextProvider, child) {
                    if (upNextProvider.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final queue = upNextProvider.videos;

                    if (queue.isEmpty) {
                      return Center(
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
                              'Queue is empty',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).disabledColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Consumer<AudioHandler>(
                      builder: (context, audioHandler, child) {
                        return StreamBuilder<MediaItem?>(
                          stream: audioHandler.mediaItem,
                          builder: (context, snapshot) {
                            final currentItem = snapshot.data;
                            return ListView.builder(
                              controller: _scrollController,
                              itemCount: queue.length + (upNextProvider.isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == queue.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                final item = queue[index];
                                final isPlaying = currentItem?.id == (item.extras?['videoId'] as String?);

                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: (item.extras?['thumbnailUrl'] as String? ?? '').isNotEmpty
                                        ? Image.network(
                                            item.extras!['thumbnailUrl'] as String,
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 40,
                                            height: 40,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.1),
                                            child: const Icon(Icons.music_note),
                                          ),
                                  ),
                                  title: Text(
                                    item.title ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight:
                                          isPlaying ? FontWeight.bold : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () async {
                                    await (audioHandler as MyAudioHandler).playFromUpNext(index);
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
            ],
          ),
        );
      },
    );
  }
}
