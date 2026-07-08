import 'package:flutter/material.dart';

class PoseScoreCard extends StatelessWidget {
  const PoseScoreCard({
    super.key,
    required this.scoreLabel,
  });

  final String scoreLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Text(
            'Độ khớp: $scoreLabel',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}