import 'package:flutter/material.dart';

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.progress,
    required this.onPlayPause,
    required this.onSeek,
    required this.onReset,
  });

  final bool isPlaying;
  final double progress;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Slider(
            value: progress.clamp(0, 1),
            onChanged: onSeek,
            activeColor: const Color(0xFFB388FF),
            inactiveColor: Colors.white24,
          ),
          Row(
            children: [
              IconButton(
                onPressed: onPlayPause,
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.replay, color: Colors.white70),
                label: const Text(
                  'Reset',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
