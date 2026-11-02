import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/legal_documents.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(document.title))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (legalDocumentsAreDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Text(
                  tr('Draft for the private beta, pending legal review.'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.terracotta,
                  ),
                ),
              ),
            for (final section in document.sections) ...[
              Text(tr(section.heading), style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tr(section.body),
                style: textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}
