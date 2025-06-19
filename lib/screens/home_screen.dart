import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/providers/library_provider.dart';
import 'package:asteroid/providers/theme_provider.dart';
import 'package:asteroid/widgets/home/horizontal_section.dart';
import 'package:asteroid/widgets/home/song_card.dart';
import 'package:asteroid/widgets/home/playlist_card.dart';
import 'package:asteroid/widgets/home/genre_card.dart';
import 'package:asteroid/screens/library_screen.dart';
import 'package:asteroid/screens/search_screen.dart';
import 'package:asteroid/widgets/player_bar.dart';
import 'package:asteroid/widgets/app_drawer.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, child) {
        return Consumer<AudioHandler>(
          builder: (context, audioHandler, child) {
            return StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              builder: (context, mediaSnapshot) {
                final currentSong = mediaSnapshot.data;
                
                return StreamBuilder<PlaybackState>(
                  stream: audioHandler.playbackState,
                  builder: (context, playbackSnapshot) {
                    final isPlaying = playbackSnapshot.data?.playing ?? false;

                    return RefreshIndicator(
                      onRefresh: () async {
                        // Reload library data
                        await library.loadLibrary();
                      },
                      child: ListView(
                        children: [
                          const SizedBox(height: 24),
                          // Welcome Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome to',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                Text(
                                  'Asteroid Music',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Recently Played Section
                          if (library.recentlyPlayed.isNotEmpty)
                            HorizontalSection(
                              title: 'Recently Played',
                              onViewAll: () {
                                DefaultTabController.of(context).animateTo(0);
                                Navigator.pushNamed(context, '/library');
                              },
                              items: library.recentlyPlayed.take(10).map((song) {
                                final isCurrentSong = currentSong?.id == song.id;
                                return SongCard(
                                  song: song,
                                  isPlaying: isCurrentSong && isPlaying,
                                  onTap: () async {
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
                              }).toList(),
                            ),

                          // Your Playlists Section
                          if (library.playlists.isNotEmpty)
                            HorizontalSection(
                              title: 'Your Playlists',
                              onViewAll: () {
                                DefaultTabController.of(context).animateTo(2);
                                Navigator.pushNamed(context, '/library');
                              },
                              items: library.playlists.entries.map((entry) {
                                return HomePlaylistCard(
                                  name: entry.key,
                                  songs: entry.value,
                                  onTap: () {
                                    DefaultTabController.of(context).animateTo(2);
                                    Navigator.pushNamed(context, '/library');
                                  },
                                );
                              }).toList(),
                            ),

                          // Genres Section
                          HorizontalSection(
                            title: 'Browse by Genre',
                            itemWidth: 120,
                            items: Genre.predefinedGenres.map((genre) {
                              return GenreCard(
                                genre: genre,
                                onTap: () {
                                  // TODO: Implement genre-based search
                                  Navigator.pushNamed(
                                    context,
                                    '/search',
                                    arguments: genre.name,
                                  );
                                },
                              );
                            }).toList(),
                          ),

                          // Favorites Preview
                          if (library.favorites.isNotEmpty)
                            HorizontalSection(
                              title: 'Your Favorites',
                              onViewAll: () {
                                DefaultTabController.of(context).animateTo(1);
                                Navigator.pushNamed(context, '/library');
                              },
                              items: library.favorites.take(10).map((song) {
                                final isCurrentSong = currentSong?.id == song.id;
                                return SongCard(
                                  song: song,
                                  isPlaying: isCurrentSong && isPlaying,
                                  onTap: () async {
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
                              }).toList(),
                            ),

                          const SizedBox(height: 24),
                        ],
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeContent(),
    SearchScreen(),
    LibraryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeProvider>(context); // Ensure HomeScreen rebuilds on theme changes
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asteroid Music'),
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _widgetOptions.elementAt(_selectedIndex),
          ),
          const PlayerBar(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
