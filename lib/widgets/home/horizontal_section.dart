import 'package:flutter/material.dart';

class HorizontalSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  final VoidCallback? onViewAll;
  final double itemHeight;
  final double itemWidth;
  final EdgeInsets padding;

  const HorizontalSection({
    super.key,
    required this.title,
    required this.items,
    this.onViewAll,
    this.itemHeight = 160,
    this.itemWidth = 160,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: const Text('View All'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: itemHeight,
          child: ListView.builder(
            padding: padding,
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) => SizedBox(
              width: itemWidth,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: items[index],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
