import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

/// Borderless tonal segmented control with a subtle elevated active thumb,
/// eliminating outer stroke and vertical divider clutter.
class FalconSegmentedTrack<T> extends StatelessWidget {
  const FalconSegmentedTrack({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.cardSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final seg in segments)
            _buildSegment(context, c, seg),
        ],
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    FalconColors c,
    ({T value, String label}) seg,
  ) {
    final isSelected = seg.value == selected;
    final tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!isSelected) onChanged(seg.value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 13),
        decoration: BoxDecoration(
          color: isSelected ? c.card : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          seg.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? c.textPrimary : c.textSecondary,
          ),
        ),
      ),
    );
    return expand ? Expanded(child: tile) : tile;
  }
}
