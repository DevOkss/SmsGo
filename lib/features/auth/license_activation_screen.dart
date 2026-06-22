import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_theme.dart';
import '../../core/constants/error_utils.dart';
import '../../providers/license_provider.dart';
import '../../services/license_service.dart';
import '../../main_shell.dart';

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({super.key});

  @override
  State<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyCodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _keyCodeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final status = await context.read<LicenseProvider>().activate(
            _keyCodeController.text.trim(),
          );

      if (!mounted) return;

      if (status == LicenseStatus.active || status == LicenseStatus.cached) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('License activated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      } else {
        String message;
        switch (status) {
          case LicenseStatus.expired:
            message = 'This license key has expired';
            break;
          case LicenseStatus.revoked:
            message = 'This license key has been revoked';
            break;
          case LicenseStatus.deviceLimitReached:
            message = 'This license key is already bound to another device. Contact admin to reassign.';
            break;
          case LicenseStatus.invalid:
            message = 'License key not found. Please check your key and try again.';
            break;
          default:
            message = 'Activation failed. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _keyCodeController.text = data!.text!;
      _keyCodeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _keyCodeController.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Key icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.vpn_key_rounded,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Activate License',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your access key to activate SmsGo on this device.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // Key input
                  TextFormField(
                    controller: _keyCodeController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _activate(),
                    decoration: InputDecoration(
                      hintText: 'SMSGO-XXXX-XXXX-XXXX',
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 20),
                        onPressed: _pasteFromClipboard,
                        tooltip: 'Paste from clipboard',
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Access key is required';
                      }
                      final pattern = RegExp(r'^SMSGO-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
                      if (!pattern.hasMatch(v.trim().toUpperCase())) {
                        return 'Format: SMSGO-XXXX-XXXX-XXXX';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Activate button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _activate,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.darkBg,
                              ),
                            )
                          : const Text('Activate'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
