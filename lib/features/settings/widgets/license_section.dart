import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_theme.dart';
import '../../../providers/license_provider.dart';
import '../../../services/license_service.dart';
import '../../auth/license_activation_screen.dart';

class LicenseSection extends StatelessWidget {
  const LicenseSection({super.key});

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseProvider>();
    final theme = Theme.of(context);

    final (statusLabel, statusColor, statusIcon) = _statusInfo(license.status);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(statusIcon, color: statusColor),
          title: const Text('License Status'),
          subtitle: Text(statusLabel),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (license.keyCode != null) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vpn_key_rounded, color: theme.colorScheme.primary),
            title: const Text('Access Key'),
            subtitle: Text(license.keyCode!),
          ),
        ],
        if (license.expiresAt != null) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_rounded, color: AppColors.info),
            title: const Text('Expires'),
            subtitle: Text(_formatDate(license.expiresAt!)),
          ),
        ],
        if (license.status == LicenseStatus.unlicensed) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary),
            title: const Text('Activate License'),
            subtitle: const Text('Enter your access key'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LicenseActivationScreen()),
              );
            },
          ),
        ],
        if (license.status != LicenseStatus.active &&
            license.status != LicenseStatus.cached &&
            license.status != LicenseStatus.unlicensed) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh_rounded, color: theme.colorScheme.primary),
            title: const Text('Retry Validation'),
            onTap: () => license.validate(),
          ),
        ],
      ],
    );
  }

  (String, Color, IconData) _statusInfo(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.active:
        return ('Active', AppColors.success, Icons.check_circle_rounded);
      case LicenseStatus.cached:
        return ('Active (offline)', AppColors.info, Icons.offline_bolt_rounded);
      case LicenseStatus.expired:
        return ('Expired', AppColors.error, Icons.error_outline_rounded);
      case LicenseStatus.revoked:
        return ('Revoked', AppColors.error, Icons.block_rounded);
      case LicenseStatus.deviceLimitReached:
        return ('Device Limit', AppColors.warning, Icons.devices_other_rounded);
      case LicenseStatus.invalid:
        return ('Invalid', AppColors.error, Icons.help_outline_rounded);
      case LicenseStatus.unlicensed:
        return ('No License', AppColors.darkSubtext, Icons.vpn_key_off_rounded);
      default:
        return ('Checking...', AppColors.darkSubtext, Icons.hourglass_top_rounded);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
