import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lead.dart';
import '../repositories/lead_repository.dart';

class ContactsProvider extends ChangeNotifier {
  final _leadRepo = LeadRepository();

  List<Lead> _contacts = [];
  List<Lead> get contacts => _contacts;
  List<Lead> get replied => _contacts.where((c) => c.replied).toList();

  bool _showRepliedOnly = false;
  bool get showRepliedOnly => _showRepliedOnly;

  List<Lead> get filtered => _showRepliedOnly ? replied : _contacts;

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    // Get all sent leads across all campaigns
    final db = await _getAll();
    _contacts = db;
    _loading = false;
    notifyListeners();
  }

  Future<List<Lead>> _getAll() async {
    // Get all leads that have been sent
    return _leadRepo.getByCampaign(0).catchError((_) => <Lead>[]);
  }

  void toggleRepliedFilter() {
    _showRepliedOnly = !_showRepliedOnly;
    notifyListeners();
  }

  Future<String> export() async {
    final list = filtered;
    final lines = ['Name,Phone,Network,Sent,Replied,Reply'];
    for (final lead in list) {
      lines.add([
        lead.name ?? '',
        lead.phoneNumber,
        lead.network,
        lead.sent ? 'Yes' : 'No',
        lead.replied ? 'Yes' : 'No',
        lead.replyMessage?.replaceAll(',', ';') ?? '',
      ].join(','));
    }
    final content = lines.join('\n');
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/smsgo_contacts_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(content);
    return file.path;
  }
}