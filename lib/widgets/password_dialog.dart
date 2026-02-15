import 'package:flutter/material.dart';

/// Password entry dialog with show/hide toggle, confirmation, and strength indicator
class PasswordDialog extends StatefulWidget {
  final bool isEncrypting;
  final String? fileName;

  const PasswordDialog({
    super.key,
    required this.isEncrypting,
    this.fileName,
  });

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void dispose() {
    // Clear sensitive data before disposing
    _passwordController.clear();
    _confirmController.clear();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // Validation
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a password';
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters';
      });
      return;
    }

    if (widget.isEncrypting && password != confirm) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    Navigator.of(context).pop(password);
  }

  /// Calculate password strength (0.0 to 1.0)
  double _calculateStrength(String password) {
    if (password.isEmpty) return 0.0;

    double score = 0.0;

    // Length scoring
    if (password.length >= 8) score += 0.15;
    if (password.length >= 12) score += 0.15;
    if (password.length >= 16) score += 0.1;
    if (password.length >= 20) score += 0.1;

    // Character variety
    if (password.contains(RegExp(r'[a-z]'))) score += 0.1;
    if (password.contains(RegExp(r'[A-Z]'))) score += 0.1;
    if (password.contains(RegExp(r'[0-9]'))) score += 0.1;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score += 0.1;

    // Non-ASCII characters (multi-alphabet bonus)
    if (password.contains(RegExp(r'[^\x00-\x7F]'))) score += 0.1;

    return score.clamp(0.0, 1.0);
  }

  /// Get strength label and colour
  ({String label, Color color}) _getStrengthInfo(double strength) {
    if (strength < 0.3) return (label: 'Weak', color: Colors.red);
    if (strength < 0.5) return (label: 'Fair', color: Colors.orange);
    if (strength < 0.7) return (label: 'Good', color: Colors.amber.shade700);
    if (strength < 0.9) return (label: 'Strong', color: Colors.green);
    return (label: 'Very Strong', color: Colors.green.shade800);
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordController.text;
    final strength = _calculateStrength(password);
    final strengthInfo = _getStrengthInfo(strength);

    return AlertDialog(
      title: Text(widget.isEncrypting ? 'Encrypt File' : 'Decrypt File'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.fileName != null) ...[
              Text(
                widget.fileName!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
            ],
            
            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              onChanged: (_) => setState(() {}), // Rebuild for strength indicator
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              onSubmitted: (_) {
                if (!widget.isEncrypting) {
                  _submit();
                }
              },
            ),
            
            // Password strength indicator (only for encryption)
            if (widget.isEncrypting && password.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: strength,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(strengthInfo.color),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    strengthInfo.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: strengthInfo.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            
            // Confirm password field (only for encryption)
            if (widget.isEncrypting) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            
            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
            
            // Warning for encryption
            if (widget.isEncrypting) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remember your password!\nLost passwords cannot be recovered.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.isEncrypting 
                ? const Color(0xFF16a34a) 
                : const Color(0xFFea580c),
            foregroundColor: Colors.white,
          ),
          child: Text(widget.isEncrypting ? 'Encrypt' : 'Decrypt'),
        ),
      ],
    );
  }
}

/// Show password dialog and return the entered password (or null if cancelled)
Future<String?> showPasswordDialog({
  required BuildContext context,
  required bool isEncrypting,
  String? fileName,
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PasswordDialog(
      isEncrypting: isEncrypting,
      fileName: fileName,
    ),
  );
}
