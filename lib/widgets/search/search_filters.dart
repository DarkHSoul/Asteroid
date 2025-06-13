import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/providers/search_provider.dart';

class SearchFilters extends StatelessWidget {
  const SearchFilters({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, searchProvider, child) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: searchProvider.currentFilter == SearchFilter.all,
                onSelected: (_) => searchProvider.setFilter(SearchFilter.all),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Songs',
                selected: searchProvider.currentFilter == SearchFilter.songs,
                onSelected: (_) => searchProvider.setFilter(SearchFilter.songs),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Artists',
                selected: searchProvider.currentFilter == SearchFilter.artists,
                onSelected: (_) => searchProvider.setFilter(SearchFilter.artists),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Albums',
                selected: searchProvider.currentFilter == SearchFilter.albums,
                onSelected: (_) => searchProvider.setFilter(SearchFilter.albums),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Function(bool) onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
        fontWeight: selected ? FontWeight.bold : null,
      ),
      backgroundColor: Theme.of(context).chipTheme.backgroundColor,
      selectedColor: Theme.of(context).primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}
