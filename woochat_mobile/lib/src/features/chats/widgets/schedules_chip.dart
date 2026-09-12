import 'package:flutter/material.dart';

import '../../../data/schedules_repository.dart';
import '../../../theme/wa_colors.dart';

/// The Schedules filter chip.
///
/// While it is off and scheduled sends are still pending, it pulses a 1px
/// accent ring — that pulse is the badge telling the user sends are waiting.
class SchedulesChip extends StatefulWidget {
  const SchedulesChip({
    super.key,
    required this.bucket,
    required this.hasPending,
    required this.onTap,
  });

  /// Null when the filter is off.
  final ScheduleBucket? bucket;

  final bool hasPending;
  final VoidCallback onTap;

  @override
  State<SchedulesChip> createState() => _SchedulesChipState();
}

class _SchedulesChipState extends State<SchedulesChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _active => widget.bucket != null;
  bool get _showsFailures =>
      widget.bucket == ScheduleBucket.failed ||
      widget.bucket == ScheduleBucket.failedActive;

  /// Only pulse while the chip is off and something is still queued.
  bool get _shouldPulse => !_active && widget.hasPending;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(SchedulesChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (_shouldPulse) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = switch (widget.bucket) {
      null => Wa.chipInactiveBackground,
      ScheduleBucket.all => Wa.chipActiveBackground,
      ScheduleBucket.failed ||
      ScheduleBucket.failedActive =>
        Wa.scheduleFailed,
    };
    final foreground = _active ? Colors.white : Wa.secondaryText;
    final label = _showsFailures ? 'Schedules - Failed' : 'Schedules';

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: _shouldPulse
                  ? Border.all(
                      color: Wa.accent.withValues(alpha: 0.25 + _pulse.value * 0.75),
                      width: 1,
                    )
                  : null,
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.schedule, size: 14, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
