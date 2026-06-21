class AppConstants {
  static const String appName = 'SmsGo';
  static const String dbName = 'smsgo.db';
  static const int dbVersion = 1;

  // Network types
  static const String networkGlobe = 'Globe';
  static const String networkSmart = 'Smart';
  static const String networkDito = 'DITO';
  static const String networkOthers = 'Others';
  static const String networkAll = 'All';

  static const List<String> networks = [
    networkAll,
    networkGlobe,
    networkSmart,
    networkDito,
    networkOthers,
  ];

  // Globe/TM prefixes (4-digit)
  static const Set<String> globePrefixes = {
    '0817', '0904', '0905', '0906', '0915', '0916', '0917',
    '0926', '0927', '0935', '0936', '0937', '0945', '0953',
    '0954', '0955', '0956', '0965', '0966', '0967', '0975',
    '0976', '0977', '0978', '0979', '0994', '0995', '0996', '0997',
  };

  // Smart/TNT/Sun prefixes (4-digit)
  static const Set<String> smartPrefixes = {
    '0813', '0907', '0908', '0909', '0910', '0911', '0912', '0913', '0914',
    '0918', '0919', '0920', '0921', '0928', '0929', '0930',
    '0938', '0939', '0946', '0947', '0948', '0949',
    '0950', '0951', '0961', '0963', '0968', '0969',
    '0980', '0981', '0989', '0998', '0999',
  };

  // DITO prefixes (4-digit)
  static const Set<String> ditoPrefixes = {
    '0895', '0896', '0897', '0898', '0991', '0992', '0993',
  };

  // Note categories
  static const String categoryRotational = 'rotational';
  static const String categorySequential = 'sequential';

  // Duration options (seconds between sends)
  static const List<int> sendDurations = [1, 2, 3, 5, 8, 10, 15, 20, 30, 60];

  // SIM slots
  static const String simSlot1 = 'SIM 1';
  static const String simSlot2 = 'SIM 2';
  static const String simBoth = 'Both';

  // Update system
  static const String envGithubOwner = 'GITHUB_OWNER';
  static const String envGithubRepo = 'GITHUB_REPO';
  static const String envUpdateCheckInterval = 'UPDATE_CHECK_INTERVAL_HOURS';
  static const String defaultGithubOwner = 'DevOkss';
  static const String defaultGithubRepo = 'SmsGo';
  static const int defaultCheckIntervalHours = 24;
  static const String lastUpdateCheckKey = 'last_update_check_timestamp';
  static const String updateSkippedVersionKey = 'update_skipped_version';
  static const String updateJsonFileName = 'update.json';
}