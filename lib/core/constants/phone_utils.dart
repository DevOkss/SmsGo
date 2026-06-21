import '../constants/app_constants.dart';

class PhoneUtils {
  static String detectNetwork(String phone) {
    final clean = cleanNumber(phone);
    if (clean.isEmpty) return AppConstants.networkOthers;

    // Normalize to 0-prefixed 11-digit PH number
    String normalized;
    if (clean.startsWith('63') && clean.length == 12) {
      normalized = '0${clean.substring(2)}';
    } else if (clean.startsWith('0') && clean.length == 11) {
      normalized = clean;
    } else if (clean.length == 10) {
      normalized = '0$clean';
    } else {
      return AppConstants.networkOthers;
    }

    final prefix = normalized.substring(0, 4);
    if (AppConstants.globePrefixes.contains(prefix)) return AppConstants.networkGlobe;
    if (AppConstants.smartPrefixes.contains(prefix)) return AppConstants.networkSmart;
    if (AppConstants.ditoPrefixes.contains(prefix)) return AppConstants.networkDito;
    return AppConstants.networkOthers;
  }

  static String cleanNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '').replaceAll('+', '');
  }

  static bool isValid(String phone) {
    final clean = cleanNumber(phone);
    if (clean.startsWith('63')) return clean.length == 12;
    if (clean.startsWith('0')) return clean.length == 11;
    return clean.length == 10;
  }

  static String normalize(String phone) {
    final clean = cleanNumber(phone);
    if (clean.startsWith('63') && clean.length == 12) return '0${clean.substring(2)}';
    if (clean.length == 10) return '0$clean';
    return clean;
  }

  static String formatDisplay(String phone) {
    final n = normalize(phone);
    if (n.length == 11) {
      return '${n.substring(0, 4)} ${n.substring(4, 7)} ${n.substring(7)}';
    }
    return phone;
  }
}