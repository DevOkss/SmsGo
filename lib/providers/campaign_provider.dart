import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/campaign.dart';
import '../models/lead.dart';
import '../repositories/campaign_repository.dart';
import '../repositories/lead_repository.dart';
import '../services/import_service.dart';
import '../services/sms_service.dart';

class CampaignProvider extends ChangeNotifier {
  final _repo = CampaignRepository();
  final _leadRepo = LeadRepository();

  List<Campaign> _campaigns = [];
  List<Campaign> get campaigns => _campaigns;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  StreamSubscription<Map<String, dynamic>>? _sendSub;
  Timer? _debounceTimer;

  CampaignProvider() {
    _sendSub = SmsService.instance.sendEvents.listen((_) {
      _debouncedReload();
    });
  }

  void _debouncedReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      load();
    });
  }

  Future<void> load({bool includeArchived = false}) async {
    _loading = true;
    notifyListeners();
    try {
      _campaigns = await _repo.getAll(includeArchived: includeArchived);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<Campaign?> getById(int id) => _repo.getById(id);

  Future<int> create(String name) async {
    final now = DateTime.now().toIso8601String();
    final id = await _repo.insert(Campaign(name: name, createdAt: now));
    await load();
    return id;
  }

  Future<void> rename(Campaign campaign, String newName) async {
    await _repo.update(campaign.copyWith(name: newName));
    await load();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await load();
  }

  Future<void> archive(int id) async {
    await _repo.archive(id);
    await load();
  }

  /// Parse file and return import result with cross-campaign leads excluded.
  /// Cross-campaign leads are filtered out of the leads list and counted.
  Future<ImportResult> parseImportFile(
    int campaignId,
    String filePath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final result = await ImportService.importFile(filePath, campaignId, onProgress: onProgress);

    if (result.leads.isEmpty) return result;

    // Find cross-campaign duplicates
    final phones = result.leads.map((l) => l.phoneNumber).toList();
    final crossCampaignRows = await _leadRepo.findCrossCampaignDuplicates(campaignId, phones);

    if (crossCampaignRows.isEmpty) return result;

    // Collect phone numbers that exist in other campaigns
    final crossCampaignPhones = crossCampaignRows.map((r) => r['phone_number'] as String).toSet();

    // Filter out cross-campaign leads
    final filteredLeads = result.leads.where((l) => !crossCampaignPhones.contains(l.phoneNumber)).toList();

    // Recount networks for the filtered leads
    final networkCounts = <String, int>{
      AppConstants.networkGlobe: 0,
      AppConstants.networkSmart: 0,
      AppConstants.networkDito: 0,
      AppConstants.networkOthers: 0,
    };
    for (final lead in filteredLeads) {
      networkCounts[lead.network] = (networkCounts[lead.network] ?? 0) + 1;
    }

    return ImportResult(
      leads: filteredLeads,
      total: result.total,
      valid: filteredLeads.length,
      invalid: result.invalid,
      fileDuplicates: result.fileDuplicates,
      crossCampaignCount: crossCampaignRows.length,
      errors: result.errors,
      networkCounts: networkCounts,
    );
  }

  /// Insert leads into campaign (after user confirms which ones to include).
  Future<void> insertLeads(int campaignId, List<Lead> leads) async {
    if (leads.isEmpty) return;
    await _leadRepo.insertMany(leads);
    await _repo.updateCounts(campaignId);
    await load();
  }

  Future<Map<String, int>> getNetworkCounts(int campaignId) =>
      _leadRepo.getNetworkCounts(campaignId);

  @override
  void dispose() {
    _sendSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
