import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/widgets/player/player_controls.dart';
import 'package:asteroid/audio_handler.dart';
import 'package:asteroid/providers/theme_provider.dart'; // Add this import
import 'package:flutter/services.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // Snap points
  static const double _collapsed = 0.10;
  // Expanded fraction will be computed dynamically in build()

  late final VoidCallback _sheetListener;

  @override
  void initState() {
    super.initState();
    _sheetListener = () {
      if (!mounted) return;
      // Defer the rebuild to the next frame to avoid triggering
      // setState() during the widget build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    _sheetController.addListener(_sheetListener);
  }

  @override
  void dispose() {
    _sheetController.removeListener(_sheetListener);
    _sheetController.dispose();
    super.dispose();
  }

  // Fully expanded (entire screen height)
  double _expandedFraction(BuildContext ctx) => 1.0;

  void _toggleSheet(BuildContext ctx) {
    if (!_sheetController.isAttached) return;
    final double expanded = _expandedFraction(ctx);
    final double current = _sheetController.size;
    final double target = current < (expanded + _collapsed) / 2
        ? expanded
        : _collapsed;
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _isCollapsed => _sheetController.isAttached
      ? _sheetController.size <= _collapsed + 0.005
      : true;

  bool get _isFullyExpanded =>
      _sheetController.isAttached ? _sheetController.size >= 0.99 : false;
  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);
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
        final AppBarTheme appBarTheme = currentTheme.appBarTheme;
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
            systemOverlayStyle:
                systemUiOverlayStyle, // Apply the determined style
            automaticallyImplyLeading: false,
            leading: _isFullyExpanded
                ? (mediaItem.artUri != null
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              mediaItem.artUri.toString(),
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : const Icon(Icons.music_note))
                : IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
            title: Text(
              mediaItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: _isFullyExpanded
                ? [
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, snapshotPlay) {
                        final bool playing =
                            snapshotPlay.data?.playing ?? false;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: () {
                                if (playing) {
                                  audioHandler.pause();
                                } else {
                                  audioHandler.play();
                                }
                              },
                            ),
                            StreamBuilder<List<MediaItem>>(
                              stream: audioHandler.queue,
                              builder: (context, queueSnapshot) {
                                final queue = queueSnapshot.data ?? [];
                                final hasNext =
                                    queue.isNotEmpty &&
                                    queue.last.id != mediaItem.id;

                                return IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: hasNext
                                      ? () async {
                                          await audioHandler.skipToNext();
                                        }
                                      : null,
                                  tooltip: hasNext
                                      ? 'Next Song'
                                      : 'No next song available',
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ]
                : null,
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (mediaItem.artUri != null)
                              AspectRatio(
                                aspectRatio: 1,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    mediaItem.artUri.toString(),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              mediaItem.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              mediaItem.artist ?? '',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 20),
                            PlayerControls(size: 1.2, showLabels: true),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Up Next draggable panel
              DraggableScrollableSheet(
                controller: _sheetController,
                minChildSize: _collapsed,
                initialChildSize: _collapsed,
                maxChildSize: 1.0,
                snap: true,
                snapSizes: [1.0],
                builder: (context, scrollController) {
                  final double chevronTurns =
                      _sheetController.isAttached && _sheetController.size < 0.5
                      ? 0.5
                      : 0.0;
                  return SafeArea(
                    top: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          SliverPersistentHeader(
                            pinned: true,
                            floating: true,
                            delegate: _UpNextHeaderDelegate(
                              onTap: () => _toggleSheet(context),
                              chevronTurns: chevronTurns,
                              controller: _sheetController,
                              collapsed: _collapsed,
                            ),
                          ),
                          if (!_isCollapsed)
                            const SliverToBoxAdapter(child: Divider(height: 1)),
                          if (!_isCollapsed)
                            Consumer<AudioHandler>(
                              builder: (context, audioHandler, child) {
                                final myAudioHandler =
                                    audioHandler as MyAudioHandler;
                                return StreamBuilder<List<MediaItem>>(
                                  stream: myAudioHandler.nextSongsStream,
                                  builder: (context, snapshot) {
                                    final upNextSongs = snapshot.data ?? [];
                                    if (upNextSongs.isEmpty) {
                                      return const SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: Center(
                                          child: Text('No upcoming songs'),
                                        ),
                                      );
                                    }
                                    return SliverList.builder(
                                      itemCount: upNextSongs.length,
                                      itemBuilder: (context, index) {
                                        final song = upNextSongs[index];
                                        final bool isCurrent =
                                            song.id ==
                                            mediaItem
                                                .id; // Check if this is the first search song
                                        final bool isFirstSearchSong =
                                            myAudioHandler
                                                .firstSearchSong
                                                ?.id ==
                                            song.id;
                                        return Dismissible(
                                          key: Key('${song.id}_$index'),
                                          direction: isCurrent
                                              ? DismissDirection.none
                                              : DismissDirection.endToStart,
                                          background: Container(
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(
                                              right: 20,
                                            ),
                                            color: Colors.red,
                                            child: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.white,
                                            ),
                                          ),
                                          confirmDismiss: (direction) async {
                                            if (isCurrent) return false;
                                            return true;
                                          },
                                          onDismissed: (_) {
                                            // Remove from up next
                                            myAudioHandler.removeFromUpNext(
                                              song.id,
                                            );
                                          },
                                          child: ListTile(
                                            leading: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                                                      color: Theme.of(context)
                                                          .primaryColor
                                                          .withOpacity(0.1),
                                                      child: const Icon(
                                                        Icons.music_note,
                                                      ),
                                                    ),
                                            ),
                                            title: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    song.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: isCurrent
                                                        ? TextStyle(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          )
                                                        : TextStyle(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                  ),
                                                ),
                                                if (isFirstSearchSong &&
                                                    index == 0)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          left: 8,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .primaryColor
                                                          .withOpacity(0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'From Search',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Theme.of(
                                                          context,
                                                        ).primaryColor,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            subtitle: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    song.artist ?? '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (index > 0 &&
                                                    !isFirstSearchSong)
                                                  Text(
                                                    'Similar',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color
                                                          ?.withOpacity(0.6),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            trailing:
                                                ReorderableDragStartListener(
                                                  index: index,
                                                  child: const Icon(
                                                    Icons.drag_handle,
                                                  ),
                                                ),
                                            onTap: () async {
                                              await myAudioHandler
                                                  .playFromUpNext(index);
                                            },
                                          ),
                                        ); // End of ListTile
                                      }, // End of itemBuilder for ReorderableListView.builder
                                    ); // End of ReorderableListView.builder
                                  }, // End of Consumer<QueueProvider> builder

                                  // End of Consumer<QueueProvider> widget
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpNextHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VoidCallback onTap;
  final double chevronTurns;
  final DraggableScrollableController controller;
  final double collapsed;

  const _UpNextHeaderDelegate({
    required this.onTap,
    required this.chevronTurns,
    required this.controller,
    required this.collapsed,
  });

  static const double _headerHeight =
      44.0; // Row (24) + padding (10 top + 10 bottom)

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final media = MediaQuery.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: (details) {
        final double delta = details.primaryDelta ?? 0;
        // Negative delta: drag up (expand) ; positive delta: drag down (collapse)
        final double screenHeight = media.size.height;
        double newSize = controller.size - delta / screenHeight;
        newSize = newSize.clamp(collapsed, 1.0);
        controller.jumpTo(newSize);
      },
      onVerticalDragEnd: (details) {
        const double velocityThreshold =
            1600; // logical pixels per second (very strong flick required)
        final double v = details.velocity.pixelsPerSecond.dy;

        double target;
        if (v > velocityThreshold) {
          // Quick downward flick – collapse
          target = collapsed;
        } else if (v < -velocityThreshold) {
          // Quick upward flick – expand
          target = 1.0;
        } else {
          // Settle based on current size
          final double mid = (collapsed + 1.0) / 2;
          target = controller.size < mid ? collapsed : 1.0;
        }

        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Up Next',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: chevronTurns,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => _headerHeight;

  @override
  double get minExtent => _headerHeight;

  @override
  bool shouldRebuild(covariant _UpNextHeaderDelegate oldDelegate) =>
      chevronTurns != oldDelegate.chevronTurns;
}
