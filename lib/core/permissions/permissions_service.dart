import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  static Future<bool> requestSmsPermissions() async {
    final results = await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
    ].request();

    final smsOk = results[Permission.sms]?.isGranted ?? false;
    final phoneOk = results[Permission.phone]?.isGranted ?? false;

    return smsOk && phoneOk;
  }
}


