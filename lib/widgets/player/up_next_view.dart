import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/audio_handler.dart';

class UpNextView extends StatelessWidget {
  const UpNextView({super.key});

  @override
  Widget build(BuildContext context) {
    final myAudioHandler = Provider.of<MyAudioHandler>(context);
    final mediaItem = myAudioHandler.mediaItem.value;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          Flexible(
            child: StreamBuilder<List<MediaItem>>(
              stream: myAudioHandler.nextSongsStream,
              builder: (context, snapshot) {
                final upNextSongs = snapshot.data ?? [];
                if (upNextSongs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('No upcoming songs'),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: upNextSongs.length,
                  itemBuilder: (context, index) {
                    final song = upNextSongs[index];
                    final bool isCurrent = song.id == mediaItem?.id;
                    return ListTile(
                      key: Key(song.id),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: song.artUri != null
                            ? Image.network(
                                song.artUri.toString(),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                child: const Icon(Icons.music_note),
                              ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isCurrent
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        song.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        await myAudioHandler.playFromUpNext(index);
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
  }
}
