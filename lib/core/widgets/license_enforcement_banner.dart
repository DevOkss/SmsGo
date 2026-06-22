import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_theme.dart';
import '../../providers/license_provider.dart';
import '../../services/license_service.dart';

class LicenseEnforcementBanner extends StatelessWidget {
  const LicenseEnforcementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseProvider>();

    // Only show for expired or revoked licenses
    if (license.status != LicenseStatus.expired &&
        license.status != LicenseStatus.revoked &&
        license.status != LicenseStatus.deviceLimitReached) {
      return const SizedBox.shrink();
    }

    final (message, color) = switch (license.status) {
      LicenseStatus.expired => ('License expired — SMS features are limited', AppColors.warning),
      LicenseStatus.revoked => ('License revoked — contact support', AppColors.error),
      LicenseStatus.deviceLimitReached => ('Device limit reached — deactivate another device', AppColors.warning),
      _ => ('', AppColors.darkSubtext),
    };

    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: color.withValues(alpha: 0.1),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: Text('Fix', style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
