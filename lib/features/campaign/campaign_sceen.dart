import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../database/database.dart';
import '../../models/campaign.dart';
import '../../models/lead.dart';
import '../../providers/campaign_provider.dart';
import '../../services/import_service.dart';
import '../../services/sms_service.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CampaignProvider>().load(includeArchived: _showArchived);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaigns'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.archive_rounded : Icons.archive_outlined),
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              context.read<CampaignProvider>().load(includeArchived: _showArchived);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'campaign_fab',
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Campaign'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CampaignProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.campaigns.isEmpty) {
            return EmptyState(
              icon: Icons.campaign_outlined,
              title: 'No campaigns',
              subtitle: 'Tap the button below to create your first campaign.',
              action: ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Campaign'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.campaigns.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = provider.campaigns[i];
              return _CampaignCard(
                campaign: c,
                onImport: () => _importLeads(c),
                onDelete: () => _confirmDelete(c),
                onArchive: () => _confirmArchive(c),
                onTap: () => _showCampaignDetail(c),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Campaign'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Campaign name',
            labelText: 'Name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await context.read<CampaignProvider>().create(controller.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _importLeads(Campaign campaign) async {
    final result = await file_picker.FilePicker.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    if (!mounted) return;

    // Progress dialog with percentage
    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>('Reading file...');

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        progressNotifier: progressNotifier,
        statusNotifier: statusNotifier,
      ),
    );

    try {
      final importResult = await context.read<CampaignProvider>().parseImportFile(
        campaign.id!,
        filePath,
        onProgress: (current, total) {
          progressNotifier.value = total > 0 ? current / total : 0;
          statusNotifier.value = 'Parsing rows... $current / $total';
        },
      );

      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.pop(context);
        _showImportPreview(campaign, importResult);
      }
    } catch (e) {
      progressNotifier.dispose();
      statusNotifier.dispose();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showImportPreview(Campaign campaign, ImportResult result) {
    final importCount = result.valid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Preview'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow('Valid Leads', '$importCount', color: AppColors.success),

              if (result.fileDuplicates > 0)
                _InfoRow('Duplicates', '${result.fileDuplicates}', color: Colors.orange.shade700),

              if (result.crossCampaignCount > 0)
                _InfoRow('Other Campaign', '${result.crossCampaignCount}'),

              if (result.invalid > 0)
                _InfoRow('Broken Leads', '${result.invalid}', color: AppColors.error),

              const Divider(height: 20),

              // Network breakdown
              _InfoRow('Globe', '${result.networkCounts[AppConstants.networkGlobe] ?? 0}'),
              _InfoRow('Smart', '${result.networkCounts[AppConstants.networkSmart] ?? 0}'),
              _InfoRow('DITO', '${result.networkCounts[AppConstants.networkDito] ?? 0}'),
              _InfoRow('Others', '${result.networkCounts[AppConstants.networkOthers] ?? 0}'),

              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Will import: $importCount new number(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Issues:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ...result.errors.take(5).map((e) => Text('• $e',
                  style: const TextStyle(fontSize: 12, color: AppColors.error))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: importCount == 0 ? null : () async {
              Navigator.pop(ctx);
              await _executeImport(campaign, result);
            },
            child: Text('Import $importCount'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeImport(
    Campaign campaign,
    ImportResult result,
  ) async {
    if (!mounted) return;

    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>('Importing...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        progressNotifier: progressNotifier,
        statusNotifier: statusNotifier,
      ),
    );

    try {
      final provider = context.read<CampaignProvider>();

      List<Lead> toImport = result.leads;

      progressNotifier.value = 0.5;
      statusNotifier.value = 'Importing new numbers...';
      await provider.insertLeads(campaign.id!, toImport);

      progressNotifier.value = 1.0;
      statusNotifier.value = 'Done!';

      await Future.delayed(const Duration(milliseconds: 300));

      progressNotifier.dispose();
      statusNotifier.dispose();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${toImport.length} number(s)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      progressNotifier.dispose();
      statusNotifier.dispose();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmDelete(Campaign c) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Delete Campaign',
      message: 'Delete "${c.name}" and all its leads? This cannot be undone.',
    );
    if (confirm && mounted) {
      await context.read<CampaignProvider>().delete(c.id!);
    }
  }

  Future<void> _confirmArchive(Campaign c) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Archive Campaign',
      message: 'Mark "${c.name}" as complete and archive it?',
      confirmLabel: 'Archive',
      confirmColor: AppColors.primary,
    );
    if (confirm && mounted) {
      await context.read<CampaignProvider>().archive(c.id!);
    }
  }

  void _showCampaignDetail(Campaign c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CampaignDetailScreen(campaign: c)),
    );
  }
}

class _ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progressNotifier;
  final ValueNotifier<String> statusNotifier;

  const _ImportProgressDialog({
    required this.progressNotifier,
    required this.statusNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        height: 120,
        child: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) {
            final pct = (progress * 100).toInt();
            return ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (_, status, __) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(status),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$pct%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? Theme.of(context).textTheme.bodyMedium?.color,
            )),
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final VoidCallback onImport;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onTap;

  const _CampaignCard({
    required this.campaign,
    required this.onImport,
    required this.onDelete,
    required this.onArchive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(campaign.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
              ),
              Row(
                children: [
                  if (campaign.completed)
                    const StatusBadge(label: 'DONE', color: AppColors.success)
                  else if (campaign.archived)
                    const StatusBadge(label: 'ARCHIVED', color: AppColors.darkSubtext),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (val) {
                      switch (val) {
                        case 'import': onImport();
                        case 'archive': onArchive();
                        case 'delete': onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      if (campaign.totalLeads == 0)
                        const PopupMenuItem(value: 'import', child: _MenuItem(Icons.upload_file_rounded, 'Import leads')),
                      if (!campaign.archived)
                        const PopupMenuItem(value: 'archive', child: _MenuItem(Icons.archive_rounded, 'Archive')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: _MenuItem(Icons.delete_rounded, 'Delete', color: AppColors.error)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (campaign.totalLeads > 0) ...[
            ProgressRow(
              sent: campaign.sentCount,
              total: campaign.totalLeads,
              failed: campaign.failedCount,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            campaign.totalLeads == 0
              ? 'No leads — tap ⋮ to import'
              : '${campaign.totalLeads} leads · ${campaign.totalLeads - campaign.sentCount} pending'
                '${campaign.totalLeads > 0 ? ' · ${(campaign.progress * 100).toStringAsFixed(0)}%' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }
}

// ─── Campaign Detail Screen ──────────────────────────────────────────────────

class CampaignDetailScreen extends StatefulWidget {
  final Campaign campaign;
  const CampaignDetailScreen({super.key, required this.campaign});

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  Map<String, int> _networkCounts = {};
  bool _loading = true;
  Campaign? _campaign;
  StreamSubscription<Map<String, dynamic>>? _sendSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
    _loadNetworkCounts();
    _sendSub = SmsService.instance.sendEvents.listen((_) {
      _debouncedRefresh();
    });
  }

  void _debouncedRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 2), () {
      _refreshCampaign();
    });
  }

  Future<void> _refreshCampaign() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('campaigns', where: 'id = ?', whereArgs: [widget.campaign.id], limit: 1);
      if (rows.isNotEmpty && mounted) {
        setState(() { _campaign = Campaign.fromMap(rows.first); });
        _loadNetworkCounts();
      }
    } catch (_) {}
  }

  Future<void> _loadNetworkCounts() async {
    final counts = await context.read<CampaignProvider>()
        .getNetworkCounts(widget.campaign.id!);
    if (mounted) setState(() { _networkCounts = counts; _loading = false; });
  }

  @override
  void dispose() {
    _sendSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign ?? widget.campaign;
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ProgressRow(sent: c.sentCount, total: c.totalLeads, failed: c.failedCount),
                const SizedBox(height: 4),
                if (c.totalLeads > 0)
                  Text('${(c.progress * 100).toStringAsFixed(0)}% complete',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.primary)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Stat('Total Leads', '${c.totalLeads}')),
                  Expanded(child: _Stat('Contacted', '${c.sentCount}', color: AppColors.success)),
                  Expanded(child: _Stat('Failed', '${c.failedCount}', color: AppColors.error)),
                  Expanded(child: _Stat('Pending', '${c.totalLeads - c.sentCount}')),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Leads by Network', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_networkCounts.isEmpty)
                  Text('No leads imported yet', style: Theme.of(context).textTheme.bodySmall)
                else
                  ..._networkCounts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        NetworkBadge(network: e.key),
                        const SizedBox(width: 10),
                        Text('${e.value} numbers',
                          style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
          style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700,
            color: color ?? Theme.of(context).textTheme.bodyLarge?.color,
          )),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
