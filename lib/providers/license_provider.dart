import 'dart:async';

import 'package:flutter/material.dart';

import '../services/license_service.dart';

/// License status exposed to the UI.
class LicenseProvider extends ChangeNotifier {
  final LicenseService _licenseService = LicenseService.instance;

  LicenseStatus _status = LicenseStatus.unknown;
  LicenseStatus get status => _status;

  LicenseCache? get cachedLicense => _licenseService.cachedLicense;
  String? get keyCode => cachedLicense?.keyCode;
  DateTime? get expiresAt => cachedLicense?.expiresAt;

  bool get isLicensed => _status == LicenseStatus.active || _status == LicenseStatus.cached;
  bool get canSendSms => _status == LicenseStatus.active || _status == LicenseStatus.cached;

  Timer? _periodicTimer;

  /// Initialize: load cache, then validate with server.
  Future<void> initialize() async {
    await _licenseService.loadCache();

    // Set initial status from cache
    if (_licenseService.cachedLicense != null) {
      _status = _licenseService.cachedLicense!.status;
      notifyListeners();
    }

    // Validate with server
    await validate();

    // Start periodic validation (every 6 hours)
    _periodicTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => validate(),
    );
  }

  /// Validate license with the server.
  Future<void> validate() async {
    _status = await _licenseService.validate();
    notifyListeners();
  }

  /// Activate a license key.
  Future<LicenseStatus> activate(String keyCode) async {
    _status = await _licenseService.activate(keyCode);
    notifyListeners();
    return _status;
  }

  /// Deactivate current device.
  Future<bool> deactivate() async {
    final success = await _licenseService.deactivate();
    if (success) {
      _status = LicenseStatus.unlicensed;
      notifyListeners();
    }
    return success;
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }
}
