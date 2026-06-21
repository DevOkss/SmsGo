import 'dart:io';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/phone_utils.dart';
import '../models/lead.dart';

class CrossCampaignDuplicate {
  final String phoneNumber;
  final int campaignId;
  final String campaignName;
  final String? name;

  CrossCampaignDuplicate({
    required this.phoneNumber,
    required this.campaignId,
    required this.campaignName,
    this.name,
  });
}

class ImportResult {
  final List<Lead> leads;
  final int total;
  final int valid;
  final int invalid;
  final int fileDuplicates;
  final int crossCampaignCount;
  final List<String> errors;
  final Map<String, int> networkCounts;
  final List<CrossCampaignDuplicate> crossCampaignDuplicates;

  ImportResult({
    required this.leads,
    required this.total,
    required this.valid,
    required this.invalid,
    required this.fileDuplicates,
    this.crossCampaignCount = 0,
    required this.errors,
    required this.networkCounts,
    this.crossCampaignDuplicates = const [],
  });
}

class ImportService {
  static Future<ImportResult> importFile(
    String filePath,
    int campaignId, {
    void Function(int current, int total)? onProgress,
  }) async {
    final ext = filePath.toLowerCase().split('.').last;
    if (ext == 'csv') return _importCsv(filePath, campaignId, onProgress: onProgress);
    if (ext == 'xlsx' || ext == 'xls') return _importExcel(filePath, campaignId, onProgress: onProgress);
    throw UnsupportedError('Unsupported file type: $ext');
  }

  static Future<ImportResult> _importCsv(
    String filePath,
    int campaignId, {
    void Function(int current, int total)? onProgress,
  }) async {
    final content = await File(filePath).readAsString();
    final rows = const CsvDecoder(escapeCharacter: '\n').convert(content);

    if (rows.isEmpty) {
      return _emptyResult(['File is empty']);
    }

    final headers = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
    final phoneCol = _findColumn(headers, ['phone', 'phone_number', 'phonenumber', 'mobile', 'number', 'contact']);
    final nameCol = _findColumn(headers, ['name', 'username', 'user_name', 'fullname', 'full_name']);

    if (phoneCol == -1) {
      return ImportResult(
        leads: [], total: 0, valid: 0, invalid: 0, fileDuplicates: 0,
        errors: ['No phone number column found. Expected: phone, mobile, number, contact'],
        networkCounts: _emptyNetworkCounts(),
        crossCampaignDuplicates: [],
      );
    }

    return _processRows(rows.skip(1).toList(), phoneCol, nameCol, campaignId, onProgress: onProgress);
  }

  static Future<ImportResult> _importExcel(
    String filePath,
    int campaignId, {
    void Function(int current, int total)? onProgress,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final sheet = excel.sheets.values.first;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      return _emptyResult(['File is empty']);
    }

    final headers = rows.first
        .map((e) => _excelCellText(e).toLowerCase().trim())
        .toList();

    final phoneCol = _findColumn(headers, ['phone', 'phone_number', 'phonenumber', 'mobile', 'number', 'contact']);
    final nameCol = _findColumn(headers, ['name', 'username', 'user_name', 'fullname', 'full_name']);

    if (phoneCol == -1) {
      return ImportResult(
        leads: [], total: 0, valid: 0, invalid: 0, fileDuplicates: 0,
        errors: ['No phone number column found. Expected: phone, mobile, number, contact'],
        networkCounts: _emptyNetworkCounts(),
        crossCampaignDuplicates: [],
      );
    }

    final rawRows = rows.skip(1).map((row) {
      return row.map(_excelCellText).toList();
    }).toList();

    return _processRows(rawRows, phoneCol, nameCol, campaignId, onProgress: onProgress);
  }

  static ImportResult _processRows(
    List<dynamic> rows, int phoneCol, int nameCol, int campaignId, {
    void Function(int current, int total)? onProgress,
  }) {
    final leads = <Lead>[];
    final seenPhones = <String>{};
    final errors = <String>[];
    int invalid = 0;
    int total = 0;
    int fileDuplicates = 0;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is List && row.length > phoneCol) {
        if (!_hasValues(row)) continue;
        total++;

        final rawPhone = row[phoneCol].toString().trim();
        if (rawPhone.isEmpty) {
          invalid++;
          if (errors.length < 5) errors.add('Row ${i + 2}: Missing phone number');
          continue;
        }

        final phone = PhoneUtils.normalize(rawPhone);
        if (!PhoneUtils.isValid(rawPhone)) {
          invalid++;
          if (errors.length < 5) errors.add('Row ${i + 2}: Invalid number "$rawPhone"');
          continue;
        }

        // File-level dedup
        if (seenPhones.contains(phone)) {
          fileDuplicates++;
          continue;
        }
        seenPhones.add(phone);

        final name = nameCol >= 0 && nameCol < row.length
            ? row[nameCol].toString().trim()
            : null;

        final network = PhoneUtils.detectNetwork(phone);
        leads.add(Lead(
          campaignId: campaignId,
          name: name?.isEmpty == true ? null : name,
          phoneNumber: phone,
          network: network,
        ));

        onProgress?.call(i + 1, rows.length);
      }
    }

    onProgress?.call(rows.length, rows.length);

    return ImportResult(
      leads: leads,
      total: total,
      valid: leads.length,
      invalid: invalid,
      fileDuplicates: fileDuplicates,
      errors: errors,
      networkCounts: _countNetworks(leads),
      crossCampaignDuplicates: [], // filled later by provider
    );
  }

  static int _findColumn(List<String> headers, List<String> candidates) {
    for (final candidate in candidates) {
      final idx = headers.indexOf(candidate);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static String _excelCellText(Data? cell) {
    final value = cell?.value;
    return switch (value) {
      null => '',
      TextCellValue() => value.value.toString(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      BoolCellValue() => value.value.toString(),
      FormulaCellValue() => value.formula,
      DateCellValue() => value.toString(),
      TimeCellValue() => value.toString(),
      DateTimeCellValue() => value.toString(),
    };
  }

  static bool _hasValues(List<dynamic> row) {
    return row.any((value) => value.toString().trim().isNotEmpty);
  }

  static ImportResult _emptyResult(List<String> errors) {
    return ImportResult(
      leads: [],
      total: 0,
      valid: 0,
      invalid: 0,
      fileDuplicates: 0,
      errors: errors,
      networkCounts: _emptyNetworkCounts(),
      crossCampaignDuplicates: [],
    );
  }

  static Map<String, int> _countNetworks(List<Lead> leads) {
    final counts = _emptyNetworkCounts();
    for (final lead in leads) {
      counts[lead.network] = (counts[lead.network] ?? 0) + 1;
    }
    return counts;
  }

  static Map<String, int> _emptyNetworkCounts() {
    return {
      AppConstants.networkGlobe: 0,
      AppConstants.networkSmart: 0,
      AppConstants.networkDito: 0,
      AppConstants.networkOthers: 0,
    };
  }
}
