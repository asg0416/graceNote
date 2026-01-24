class AccountExistsException implements Exception {
  final String message;
  final String? maskedEmail;
  final String? fullName;

  AccountExistsException({
    required this.message,
    this.maskedEmail,
    this.fullName,
  });

  @override
  String toString() => 'AccountExistsException: $message (Email: $maskedEmail)';
}
