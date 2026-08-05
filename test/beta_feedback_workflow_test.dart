import 'package:cotravel_app/features/beta/application/beta_feedback_controller.dart';
import 'package:cotravel_app/features/beta/data/beta_feedback_repository.dart';
import 'package:cotravel_app/features/beta/domain/beta_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BetaFeedbackController controller;

  setUp(() async {
    controller = BetaFeedbackController(PreviewBetaFeedbackRepository());
    await controller.load();
  });

  tearDown(() => controller.dispose());

  test('submits a structured safe-and-informed response', () async {
    final response = await controller.submit(
      const BetaFeedbackDraft(
        experienceArea: BetaExperienceArea.coordination,
        safeInformedScore: 4,
        comments: '  The group state was clear after confirmation.  ',
      ),
    );

    expect(response.isPositive, isTrue);
    expect(response.comments, 'The group state was clear after confirmation.');
    expect(controller.feedback, hasLength(1));
    expect(
      controller.feedback.single.experienceArea,
      BetaExperienceArea.coordination,
    );
  });

  test('rejects a score outside the five-point scale', () async {
    await expectLater(
      controller.submit(
        const BetaFeedbackDraft(
          experienceArea: BetaExperienceArea.discovery,
          safeInformedScore: 0,
          comments: '',
        ),
      ),
      throwsArgumentError,
    );
  });
}
