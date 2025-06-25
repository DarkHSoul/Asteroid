import 'package:flutter/material.dart';
import 'package:asteroid/widgets/player/up_next_view.dart';
import 'package:asteroid/widgets/player/lyrics_list_view.dart';
import 'package:asteroid/widgets/player/similar_songs_view.dart';

class PlayerBottomSheet extends StatefulWidget {
  final int initialIndex;

  const PlayerBottomSheet({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<PlayerBottomSheet> createState() => _PlayerBottomSheetState();
}

class _PlayerBottomSheetState extends State<PlayerBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Up Next'),
              Tab(text: 'Lyrics'),
              Tab(text: 'Similar'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                UpNextView(),
                LyricsListView(),
                SimilarSongsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
