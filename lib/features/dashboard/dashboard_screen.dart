import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../models/campaign.dart';
import '../../models/sending_session.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/device_sim_gateway.dart';
import '../../services/sms_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<DashboardProvider>().load(),
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: provider.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatsRow(
                  campaigns: provider.totalCampaigns,
                  sent: provider.totalSent,
                  active: provider.activeSessions.length,
                ),
                const SizedBox(height: 20),
                const _DeviceSimStatusSection(),
                const SizedBox(height: 18),
                if (provider.activeSessions.isNotEmpty) ...[
                  const SectionHeader(title: 'Active Sendings'),
                  const SizedBox(height: 12),
                  ...provider.activeSessions.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ActiveSessionCard(session: s, dispatchedCount: provider.dispatchedCounts[s.id] ?? 0),
                  )),
                  const SizedBox(height: 8),
                ],
                const SectionHeader(title: 'Campaigns'),
                const SizedBox(height: 12),
                if (provider.campaigns.isEmpty)
                  const EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No campaigns yet',
                    subtitle: 'Create a campaign from the Campaigns tab to get started.',
                  )
                else
                  ...provider.campaigns.take(5).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CampaignSummaryCard(campaign: c),
                  )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int campaigns;
  final int sent;
  final int active;

  const _StatsRow({required this.campaigns, required this.sent, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: 'Campaigns', value: '$campaigns', icon: Icons.campaign_rounded, color: AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Total Sent', value: '$sent', icon: Icons.send_rounded, color: AppColors.accent)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Active', value: '$active', icon: Icons.play_circle_outline_rounded, color: AppColors.warning)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final SendingSession session;
  final int dispatchedCount;

  const _ActiveSessionCard({required this.session, this.dispatchedCount = 0});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaign #${session.campaignId}',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${session.simSlot} · ${session.targetNetwork}',
                      style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text('Monitor: ${session.monitorNumber ?? 'None'}',
                      style: Theme.of(context).textTheme.bodySmall),

                  ],
                ),
              ),
              Row(
                children: [
                  StatusBadge(
                    label: session.stopped
                        ? 'STOPPED'
                        : (!session.running && !session.paused && (session.sentCount + session.failedCount >= session.totalTargets))
                            ? 'COMPLETED'
                            : (session.running ? 'RUNNING' : (session.paused ? 'PAUSED' : 'STOPPED')),
                    color: session.stopped
                        ? AppColors.darkSubtext
                        : (!session.running && !session.paused && (session.sentCount + session.failedCount >= session.totalTargets))
                            ? AppColors.success
                            : (session.running ? AppColors.success : AppColors.darkSubtext),
                  ),
                  if (session.running || session.paused) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.stop_circle_rounded, color: AppColors.error),
                      onPressed: () => context.read<DashboardProvider>().stopSession(session.id!),
                      tooltip: 'Stop',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressRow(
            sent: session.sentCount,
            total: session.totalTargets,
            failed: session.failedCount,
            dispatched: dispatchedCount,
          ),
        ],
      ),
    );
  }
}

class _DeviceSimStatusSection extends StatefulWidget {
  const _DeviceSimStatusSection();

  @override
  State<_DeviceSimStatusSection> createState() => _DeviceSimStatusSectionState();
}

class _DeviceSimStatusSectionState extends State<_DeviceSimStatusSection> {
  bool _loading = true;
  List<Map<String, dynamic>> _sims = const [];
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _simSub;
  DateTime? _lastSimUpdate;
  Timer? _throttleTimer;
  Map<String, dynamic>? _pendingUpdate;

  @override
  void initState() {
    super.initState();
    _load();
    // Subscribe to native sim signal updates with throttling (max once per 5s)
    _simSub = SmsService.instance.simStream.listen((update) {
      if (!mounted) return;
      _pendingUpdate = update;
      final now = DateTime.now();
      if (_lastSimUpdate == null || now.difference(_lastSimUpdate!) >= const Duration(seconds: 5)) {
        _lastSimUpdate = now;
        _applySimUpdate(_pendingUpdate!);
      } else {
        _throttleTimer?.cancel();
        _throttleTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _pendingUpdate != null) {
            _lastSimUpdate = DateTime.now();
            _applySimUpdate(_pendingUpdate!);
          }
        });
      }
    });
  }

  void _applySimUpdate(Map<String, dynamic> update) {
    setState(() {
      try {
        final subId = update['subscriptionId'];
        if (subId == null) return;
        for (var i = 0; i < _sims.length; i++) {
          final sim = _sims[i];
          if (sim['subscriptionId'] == subId) {
            final newSim = Map<String, dynamic>.from(sim);
            if (update.containsKey('signalDbm')) newSim['signalDbm'] = update['signalDbm'];
            if (update.containsKey('signalAsu')) newSim['signalAsu'] = update['signalAsu'];
            _sims = List<Map<String, dynamic>>.from(_sims);
            _sims[i] = newSim;
            break;
          }
        }
      } catch (e) {
        // ignore
      }
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _simSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sims = await DeviceSimGateway.getDeviceSimStatus();
      if (!mounted) return;
      setState(() {
        _sims = sims;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device SIM Status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text('Failed to load SIM status: $_error', style: Theme.of(context).textTheme.bodySmall)
            else if (_sims.isEmpty)
              const EmptyState(
                icon: Icons.sim_card_outlined,
                title: 'No SIM info',
                subtitle: 'Unable to read SIM information on this device.',
              )
            else
              Column(
                children: _sims.map((sim) {
                  final slotIndex = (sim['slotIndex'] ?? sim['slot'] ?? sim['index'] ?? '').toString();
                  final carrier = (sim['carrier'] ?? '').toString();
                  final phoneNumber = (sim['phoneNumber'] ?? '').toString();


                  int? signalDbm;
                  final rawDbm = sim['signalDbm'];
                  if (rawDbm is int) {
                    signalDbm = rawDbm;
                  } else if (rawDbm is num) {
                    signalDbm = rawDbm.toInt();
                  } else if (rawDbm is String) {
                    signalDbm = int.tryParse(rawDbm);
                  }

                  int? signalAsu;
                  final rawAsu = sim['signalAsu'];
                  if (rawAsu is int) {
                    signalAsu = rawAsu;
                  } else if (rawAsu is num) {
                    signalAsu = rawAsu.toInt();
                  } else if (rawAsu is String) {
                    signalAsu = int.tryParse(rawAsu);
                  }

                  final signal = <String, dynamic>{
                    'signalDbm': signalDbm,
                    'signalAsu': signalAsu,
                  };

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).cardColor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SIM $slotIndex', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text('Carrier: ${carrier.isEmpty ? 'Unknown' : carrier}', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text('Number: ${phoneNumber.isEmpty ? 'Unknown' : phoneNumber}', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 10),
                          _SignalBars(signal),
                        ],
                      ),
                    ),
                  );

                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final Object? signal;
  const _SignalBars(this.signal);

  @override
  Widget build(BuildContext context) {
    // Native provides:
    // signalDbm: int? (preferred)
    // signalAsu: int? (fallback)
      int? dbm;
final m = signal is Map ? (signal as Map<dynamic, dynamic>?) : null;
if (m != null) {
      final dbmObj = (m as Map<dynamic, dynamic>?)?['signalDbm'];
      if (dbmObj is int) dbm = dbmObj;
    }
    // ignore analyzer for index access; runtime-safe due to type checks above



    if (dbm == null) {
      int? asu;
      if (signal is Map) {
final maybeAsuObj = (signal as Map<dynamic, dynamic>?)?['signalAsu'];
        if (maybeAsuObj is int) asu = maybeAsuObj;
      }



      // asu -> dBm approximation: dBm = -113 + 2*asu (for GSM asu)
      if (asu != null) {
        dbm = -113 + (2 * asu);
      }
    }


    // Typical approximation bands for dBm.
    // If dBm isn't available, we compute from asu using the existing fallback.
    int bars;
    if (dbm == null) {
      bars = 0;
    } else if (dbm >= -70) {
      bars = 3;
    } else if (dbm >= -85) {
      bars = 2;
    } else if (dbm >= -100) {
      bars = 1;
    } else {
      bars = 0;
    }


    Color barColor(int index) {
      // index: 0..2 (left->right). Use primary when active.
      return index < bars ? AppColors.success : AppColors.darkSubtext;
    }

    Widget bar(int index) {
      return Expanded(
        child: Container(
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: barColor(index),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 0),
        Row(
          children: [
            SizedBox(width: 8, child: Text('', style: Theme.of(context).textTheme.bodySmall)),
            bar(0),
            bar(1),
            bar(2),
          ],
        ),
      ],
    );
  }
}

class _CampaignSummaryCard extends StatelessWidget {
  final Campaign campaign;


  const _CampaignSummaryCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final pct = campaign.totalLeads > 0
        ? (campaign.sentCount / campaign.totalLeads * 100).toStringAsFixed(0)
        : '0';

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(campaign.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${campaign.sentCount} / ${campaign.totalLeads} sent',
                  style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text('$pct%',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: campaign.totalLeads > 0 && campaign.sentCount >= campaign.totalLeads
                  ? AppColors.success
                  : AppColors.primary,
            )),
        ],
      ),
    );
  }
}