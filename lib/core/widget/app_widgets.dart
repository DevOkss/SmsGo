import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: color != null
          ? BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: child,
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class NetworkBadge extends StatelessWidget {
  final String network;

  const NetworkBadge({super.key, required this.network});

  Color get _color {
    switch (network.toLowerCase()) {
      case 'globe': return AppColors.globe;
      case 'smart': return AppColors.smart;
      case 'dito': return AppColors.dito;
      default: return AppColors.others;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatusBadge(label: network, color: _color);
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: primary.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text(title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class ProgressRow extends StatelessWidget {
  final int sent;
  final int total;
  final int failed;
  final int dispatched;
  final int startIndex;
  final int endIndex;

  const ProgressRow({
    super.key,
    required this.sent,
    required this.total,
    required this.failed,
    this.dispatched = 0,
    this.startIndex = 1,
    this.endIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final useRange = endIndex > 0;
    final displayTotal = useRange ? endIndex : total;
    final displayCurrent = useRange ? (startIndex + (dispatched > 0 ? dispatched : sent)) : (dispatched > 0 ? dispatched : sent);
    final progress = displayTotal > 0 ? displayCurrent / displayTotal : 0.0;
    final remaining = (displayTotal - displayCurrent).clamp(0, 1 << 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$displayCurrent / $displayTotal sent', style: Theme.of(context).textTheme.bodySmall),
            if (failed > 0)
              Text('$failed failed',
                style: const TextStyle(color: AppColors.error, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: primary.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(primary),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

class AppChipGroup extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const AppChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: isSelected,
          onSelected: (_) => onSelected(opt),
          selectedColor: AppColors.primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : null,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        );
      }).toList(),
    );
  }
}

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color? confirmColor;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.confirmColor,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    Color? confirmColor,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor ?? AppColors.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
