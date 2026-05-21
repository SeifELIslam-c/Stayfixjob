import 'package:intl/intl.dart';

class PhoneDisplay {
  final String flag;
  final String dialCode;
  final String number;

  const PhoneDisplay({
    required this.flag,
    required this.dialCode,
    required this.number,
  });

  String get formatted {
    final prefix = dialCode.isEmpty ? '' : '+$dialCode ';
    return '$flag $prefix$number'.trim();
  }
}

const Map<String, String> _dialCodeToCountryIso = {
  '1': 'CA',
  '7': 'RU',
  '20': 'EG',
  '27': 'ZA',
  '30': 'GR',
  '31': 'NL',
  '32': 'BE',
  '33': 'FR',
  '34': 'ES',
  '39': 'IT',
  '44': 'GB',
  '49': 'DE',
  '52': 'MX',
  '55': 'BR',
  '90': 'TR',
  '91': 'IN',
  '212': 'MA',
  '213': 'DZ',
  '216': 'TN',
  '971': 'AE',
};

String? inferCountryIsoFromDialCode(String dialCode) {
  final cleanDialCode = dialCode.replaceAll('+', '').trim();
  return _dialCodeToCountryIso[cleanDialCode];
}

String inferDialCodeFromPhone(String phone) {
  final cleanPhone = phone.trim();
  if (!cleanPhone.startsWith('+')) return '';

  final digits = cleanPhone.replaceFirst('+', '').replaceAll(RegExp(r'\D'), '');
  final knownCodes = _dialCodeToCountryIso.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final code in knownCodes) {
    if (digits.startsWith(code)) return code;
  }

  return RegExp(r'^\+(\d{1,4})').firstMatch(cleanPhone)?.group(1) ?? '';
}

String stripDialCodeFromPhone(String phone, String dialCode) {
  var cleanPhone = phone.trim();
  final cleanDialCode = dialCode.replaceAll('+', '').trim();

  if (cleanDialCode.isEmpty) return cleanPhone;

  final plusPrefix = '+$cleanDialCode';
  final doubleZeroPrefix = '00$cleanDialCode';

  if (cleanPhone.startsWith(plusPrefix)) {
    cleanPhone = cleanPhone.substring(plusPrefix.length);
  } else if (cleanPhone.startsWith(doubleZeroPrefix)) {
    cleanPhone = cleanPhone.substring(doubleZeroPrefix.length);
  }

  return cleanPhone.trimLeft();
}

DateTime? parseProfileDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  for (final format in ['dd/MM/yyyy', 'yyyy-MM-dd']) {
    try {
      return DateFormat(format).parseStrict(trimmed);
    } catch (_) {
      // Try the next supported profile date format.
    }
  }

  return null;
}

String formatProfileDate(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

bool isAtLeastAge(DateTime birthDate, int age, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var years = now.year - birthDate.year;
  final hadBirthday =
      now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!hadBirthday) years--;
  return years >= age;
}

String flagEmojiFromCountryCode(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code.length != 2) return '';

  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 65 || first > 90 || second < 65 || second > 90) return '';

  return String.fromCharCodes([first + 127397, second + 127397]);
}

PhoneDisplay buildPhoneDisplay({
  required String phone,
  String? countryIso,
  String? dialCode,
}) {
  var cleanPhone = phone.trim();
  var cleanDialCode = inferDialCodeFromPhone(cleanPhone);
  if (cleanDialCode.isEmpty) {
    cleanDialCode = (dialCode ?? '').replaceAll('+', '').trim();
  }

  cleanPhone = stripDialCodeFromPhone(cleanPhone, cleanDialCode);

  final cleanCountryIso =
      inferCountryIsoFromDialCode(cleanDialCode) ?? countryIso ?? '';
  final flag = flagEmojiFromCountryCode(cleanCountryIso);

  if (cleanDialCode.isEmpty && cleanPhone.startsWith('+')) {
    final match = RegExp(r'^\+(\d{1,4})\s*(.*)$').firstMatch(cleanPhone);
    if (match != null) {
      cleanDialCode = match.group(1) ?? '';
      cleanPhone = match.group(2)?.trim() ?? cleanPhone;
    }
  }

  return PhoneDisplay(flag: flag, dialCode: cleanDialCode, number: cleanPhone);
}
