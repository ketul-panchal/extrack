/// How numbers are grouped and where the currency symbol goes.
enum NumberStyle {
  /// 1,234,567.89 with the symbol in front.
  western('1,234,567.89', ',', '.', symbolFirst: true),

  /// 12,34,567.89 (lakh/crore grouping) with the symbol in front.
  indian('12,34,567.89', ',', '.', symbolFirst: true),

  /// 1.234.567,89 with the symbol after.
  european('1.234.567,89', '.', ',', symbolFirst: false),

  /// 1 234 567,89 with the symbol after.
  spaced('1 234 567,89', ' ', ',', symbolFirst: false);

  const NumberStyle(
    this.sample,
    this.groupSeparator,
    this.decimalSeparator, {
    required this.symbolFirst,
  });

  final String sample;
  final String groupSeparator;
  final String decimalSeparator;
  final bool symbolFirst;
}

class Currency {
  const Currency(
    this.code,
    this.symbol,
    this.name, {
    this.decimals = 2,
    this.style = NumberStyle.western,
  });

  final String code;
  final String symbol;
  final String name;

  /// Digits after the decimal point (0 for JPY, 3 for KWD).
  final int decimals;

  /// The grouping most people using this currency expect by default.
  final NumberStyle style;

  static Currency byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => all.first);

  /// Best guess for a device locale like `en_IN` or `de-DE`.
  static Currency forLocale(String? countryCode) {
    final code = switch (countryCode?.toUpperCase()) {
      'IN' => 'INR',
      'US' || 'PR' || 'EC' || 'SV' => 'USD',
      'GB' || 'IM' || 'JE' || 'GG' => 'GBP',
      'DE' ||
      'FR' ||
      'IT' ||
      'ES' ||
      'NL' ||
      'BE' ||
      'AT' ||
      'IE' ||
      'PT' ||
      'FI' ||
      'GR' ||
      'SK' ||
      'SI' ||
      'LU' ||
      'LV' ||
      'LT' ||
      'EE' ||
      'MT' ||
      'CY' ||
      'HR' => 'EUR',
      'JP' => 'JPY',
      'CN' => 'CNY',
      'AU' => 'AUD',
      'CA' => 'CAD',
      'CH' || 'LI' => 'CHF',
      'SG' => 'SGD',
      'AE' => 'AED',
      'SA' => 'SAR',
      'HK' => 'HKD',
      'NZ' => 'NZD',
      'KR' => 'KRW',
      'BR' => 'BRL',
      'MX' => 'MXN',
      'ZA' => 'ZAR',
      'TR' => 'TRY',
      'SE' => 'SEK',
      'NO' => 'NOK',
      'DK' => 'DKK',
      'PL' => 'PLN',
      'ID' => 'IDR',
      'MY' => 'MYR',
      'PH' => 'PHP',
      'TH' => 'THB',
      'VN' => 'VND',
      'PK' => 'PKR',
      'BD' => 'BDT',
      'LK' => 'LKR',
      'NP' => 'NPR',
      'EG' => 'EGP',
      'NG' => 'NGN',
      'KE' => 'KES',
      'IL' => 'ILS',
      'UA' => 'UAH',
      'QA' => 'QAR',
      'KW' => 'KWD',
      _ => 'USD',
    };
    return byCode(code);
  }

  static const all = <Currency>[
    Currency('USD', r'$', 'US Dollar'),
    Currency('EUR', '€', 'Euro', style: NumberStyle.european),
    Currency('GBP', '£', 'British Pound'),
    Currency('INR', '₹', 'Indian Rupee', style: NumberStyle.indian),
    Currency('JPY', '¥', 'Japanese Yen', decimals: 0),
    Currency('CNY', '¥', 'Chinese Yuan'),
    Currency('AUD', r'A$', 'Australian Dollar'),
    Currency('CAD', r'C$', 'Canadian Dollar'),
    Currency('CHF', 'CHF', 'Swiss Franc'),
    Currency('SGD', r'S$', 'Singapore Dollar'),
    Currency('AED', 'AED', 'UAE Dirham'),
    Currency('SAR', 'SAR', 'Saudi Riyal'),
    Currency('HKD', r'HK$', 'Hong Kong Dollar'),
    Currency('NZD', r'NZ$', 'New Zealand Dollar'),
    Currency('KRW', '₩', 'South Korean Won', decimals: 0),
    Currency('BRL', r'R$', 'Brazilian Real', style: NumberStyle.european),
    Currency('MXN', r'$', 'Mexican Peso'),
    Currency('ZAR', 'R', 'South African Rand', style: NumberStyle.spaced),
    Currency('RUB', '₽', 'Russian Ruble', style: NumberStyle.spaced),
    Currency('TRY', '₺', 'Turkish Lira', style: NumberStyle.european),
    Currency('SEK', 'kr', 'Swedish Krona', style: NumberStyle.spaced),
    Currency('NOK', 'kr', 'Norwegian Krone', style: NumberStyle.spaced),
    Currency('DKK', 'kr', 'Danish Krone', style: NumberStyle.european),
    Currency('PLN', 'zł', 'Polish Złoty', style: NumberStyle.spaced),
    Currency('IDR', 'Rp', 'Indonesian Rupiah', decimals: 0, style: NumberStyle.european),
    Currency('MYR', 'RM', 'Malaysian Ringgit'),
    Currency('PHP', '₱', 'Philippine Peso'),
    Currency('THB', '฿', 'Thai Baht'),
    Currency('VND', '₫', 'Vietnamese Dong', decimals: 0, style: NumberStyle.european),
    Currency('PKR', 'Rs', 'Pakistani Rupee'),
    Currency('BDT', '৳', 'Bangladeshi Taka', style: NumberStyle.indian),
    Currency('LKR', 'Rs', 'Sri Lankan Rupee'),
    Currency('NPR', 'Rs', 'Nepalese Rupee', style: NumberStyle.indian),
    Currency('EGP', 'E£', 'Egyptian Pound'),
    Currency('NGN', '₦', 'Nigerian Naira'),
    Currency('KES', 'KSh', 'Kenyan Shilling'),
    Currency('ILS', '₪', 'Israeli Shekel'),
    Currency('UAH', '₴', 'Ukrainian Hryvnia', style: NumberStyle.spaced),
    Currency('QAR', 'QR', 'Qatari Riyal'),
    Currency('KWD', 'KD', 'Kuwaiti Dinar', decimals: 3),
  ];
}
