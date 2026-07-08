import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoga_mirror/core/utils/angle_utils.dart';
import 'package:yoga_mirror/features/yoga_mirror/widgets/pose_score_card.dart';

void main() {
  test('calculateAngle returns ~90 for right angle', () {
    final angle = calculateAngle(
      const Offset(0, 0),
      const Offset(0, 1),
      const Offset(1, 1),
    );
    expect(angle, closeTo(90, 0.5));
  });

  testWidgets('PoseScoreCard renders score label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PoseScoreCard(scoreLabel: '72%'),
        ),
      ),
    );

    expect(find.text('Độ khớp: 72%'), findsOneWidget);
  });
}