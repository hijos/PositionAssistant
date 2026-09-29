import 'package:flutter/material.dart';

/// Shared presentation formatting for holdings figures.
///
/// The overview card, the holdings list and the holding detail page must show
/// amounts and rates with identical rules, so every caller formats through
/// these helpers instead of repeating `toStringAsFixed(2)`.
const String _placeholderDash = '—';

/// Loose numeric parsing: unusable values (including `null`) become `0`.
///
/// Only use this where a missing value is impossible, for example shares that
/// always exist on a holding record.
double parseNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

/// Strict numeric parsing: unusable values stay `null`.
///
/// Aggregates such as market value and profit must keep the difference between
/// "no data" and a real `0`, so they never fall back to zero.
double? parseNumberOrNull(dynamic value) {
  if (value == null) return null;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

/// `2106.1` -> `￥2106.10`; a missing value renders as `—`.
String formatMoney(dynamic value) {
  final number = parseNumberOrNull(value);
  if (number == null) return _placeholderDash;
  return '￥${number.toStringAsFixed(2)}';
}

/// `0.0274` -> `2.74%`; a missing value renders as `—`.
String formatRate(dynamic value) {
  final number = parseNumberOrNull(value);
  if (number == null) return _placeholderDash;
  return '${(number * 100).toStringAsFixed(2)}%';
}

/// `8` -> `8.00`, used for shares and net asset values.
String formatNumber(dynamic value) => parseNumber(value).toStringAsFixed(2);

/// `56.1`, `0.0274` -> `￥56.10（2.74%）`; `—` when the amount is unknown.
///
/// Chinese parentheses are used consistently across the overview card, the
/// holdings list and the holding detail page.
String formatMoneyWithRate(dynamic amount, dynamic rate) {
  if (parseNumberOrNull(amount) == null) return _placeholderDash;
  return '${formatMoney(amount)}（${formatRate(rate)}）';
}

/// Positive returns use the project's success green, negative ones the red
/// used elsewhere in the client, and flat/unknown values the plain text color.
Color profitColor(BuildContext context, dynamic value) {
  final number = parseNumberOrNull(value);
  if (number == null || number == 0) {
    return Theme.of(context).colorScheme.onSurface;
  }
  return number > 0 ? Colors.green.shade700 : Colors.red.shade700;
}
