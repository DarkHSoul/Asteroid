import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/widgets/player/player_controls.dart';
import 'package:asteroid/audio_handler.dart';
import 'package:asteroid/providers/theme_provider.dart';
import 'package:asteroid/widgets/player/album_art.dart';
import 'package:asteroid/widgets/player/track_info.dart';
import 'package:asteroid/widgets/player/player_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:asteroid/screens/artist_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PageController _pageController = PageController();
  PersistentBottomSheetController? _sheetController;
  bool _isSheetOpen = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPlayerBottomSheet(BuildContext scaffoldContext, int initialIndex) {
    if (_sheetController != null) {
      _sheetController!.close();
      return;
    }

    setState(() {
      _isSheetOpen = true;
    });

    _sheetController = showBottomSheet(
      context: scaffoldContext,
      builder: (context) => PlayerBottomSheet(initialIndex: initialIndex),
    );

    _sheetController!.closed.then((_) {
      if (mounted) {
        setState(() {
          _sheetController = null;
          _isSheetOpen = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<MyAudioHandler>(context);
    Provider.of<ThemeProvider>(
      context,
    ); // Ensure this widget rebuilds on theme changes

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        if (mediaItem == null) {
          // It's good practice to also set a default SystemUiOverlayStyle here
          // if this Scaffold can be visible for any significant time.
          // For now, assuming it's a brief state.
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('No song selected')),
          );
        }

        // Determine SystemUiOverlayStyle based on AppBar's effective background color
        final ThemeData currentTheme = Theme.of(context);
        var appBarTheme = currentTheme.appBarTheme;
        final Color appBarEffectiveBackgroundColor;

        if (appBarTheme.backgroundColor != null) {
          appBarEffectiveBackgroundColor = appBarTheme.backgroundColor!;
        } else {
          // Fallback logic for M2/M3 themes if appBarTheme.backgroundColor is null
          if (currentTheme.useMaterial3) {
            // M3 typically uses colorScheme.surface for default AppBar background
            // or surfaceContainer for elevated AppBars.
            // Adjust if your M3 theme customizes AppBar differently.
            appBarEffectiveBackgroundColor = currentTheme.colorScheme.surface;
          } else {
            // M2 default AppBar color is primaryColor
            appBarEffectiveBackgroundColor = currentTheme.primaryColor;
          }
        }

        final Brightness appBarBrightness =
            ThemeData.estimateBrightnessForColor(
              appBarEffectiveBackgroundColor,
            );
        final SystemUiOverlayStyle systemUiOverlayStyle =
            appBarBrightness == Brightness.dark
            ? SystemUiOverlayStyle
                  .light // Dark AppBar background -> Light status bar icons
            : SystemUiOverlayStyle
                  .dark; // Light AppBar background -> Dark status bar icons

        return Scaffold(
          appBar: AppBar(
            systemOverlayStyle: systemUiOverlayStyle,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              mediaItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: _isSheetOpen
                ? [
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, snapshot) {
                        final playbackState = snapshot.data;
                        final isPlaying = playbackState?.playing ?? false;
                        return IconButton(
                          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: isPlaying ? audioHandler.pause : audioHandler.play,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: audioHandler.skipToNext,
                    ),
                  ]
                : [],
          ),
          body: Builder(
            builder: (scaffoldContext) => ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                AlbumArt(imageUrl: mediaItem.artUri?.toString()),
                const SizedBox(height: 20),
                TrackInfo(
                  title: mediaItem.title,
                  artist: mediaItem.artist,
                  onArtistTap: () {
                    if (mediaItem.artist != null) {
                      Navigator.of(context).pop(); // Close the player screen
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => Provider.value(
                            value: audioHandler,
                            child: ArtistScreen(artistName: mediaItem.artist!),
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                PlayerControls(size: 1.2, showLabels: true),
              ],
            ),
          ),
          bottomNavigationBar: Builder(
            builder: (scaffoldContext) => BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.playlist_play_rounded),
                    onPressed: () => _showPlayerBottomSheet(scaffoldContext, 0),
                    tooltip: 'Up Next',
                  ),
                  IconButton(
                    icon: const Icon(Icons.lyrics_outlined),
                    onPressed: () => _showPlayerBottomSheet(scaffoldContext, 1),
                    tooltip: 'Lyrics',
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded),
                    onPressed: () => _showPlayerBottomSheet(scaffoldContext, 2),
                    tooltip: 'Similar',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
