import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:asteroid/widgets/library/recently_played_section.dart';
import 'package:asteroid/widgets/library/favorites_section.dart';
import 'package:asteroid/widgets/library/playlists_section.dart';
import 'package:asteroid/providers/library_provider.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load library data when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LibraryProvider>(context, listen: false).loadLibrary();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.history),
              text: 'Recent',
            ),            Tab(
              icon: Icon(Icons.favorite),
              text: 'Favorites',
            ),
            Tab(
              icon: Icon(Icons.queue_music),
              text: 'Playlists',
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              RecentlyPlayedSection(audioHandler: audioHandler),
              FavoritesSection(audioHandler: audioHandler),
              PlaylistsSection(audioHandler: audioHandler),
            ],
          ),
        ),
      ],
    );
  }
}
