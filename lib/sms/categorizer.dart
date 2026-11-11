import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

/// The groups Sift sorts the inbox into, in display order.
enum SmsCategory {
  otp('OTPs & codes', 'Verification and login codes', Icons.password_rounded, UiStatus.info),
  bank('Bank & payments', 'Debits, credits, UPI and card alerts', Icons.account_balance_rounded, UiStatus.success),
  orders('Orders & deliveries', 'Shipping, delivery and booking updates', Icons.local_shipping_rounded, UiStatus.warning),
  promotions('Promotions & offers', 'Sales, cashback, loans and other ads', Icons.campaign_rounded, UiStatus.danger),
  updates('Alerts & updates', 'Other messages from companies and services', Icons.notifications_rounded, UiStatus.accent),
  personal('Personal', 'Messages from phone numbers', Icons.person_rounded, UiStatus.neutral);

  const SmsCategory(this.label, this.description, this.icon, this.status);

  final String label;
  final String description;
  final IconData icon;
  final UiStatus status;
}

/// Sorts one SMS into a [SmsCategory] with keyword rules. Runs on the phone only.
///
/// Order matters: OTP, then bank, then clear promotions, then orders, then
/// weaker promotions, then personal (sender is a phone number), else updates.
class SmsCategorizer {
  const SmsCategorizer._();

  static SmsCategory categorize(String address, String body) {
    final text = body.toLowerCase();
    final fromPerson = isPhoneNumber(address);

    if (_isOtp(text)) return SmsCategory.otp;
    if (_isBank(text)) return SmsCategory.bank;
    final promo = promoScore(address, text);
    if (promo >= 2) return SmsCategory.promotions;
    if (_order.hasMatch(text)) return SmsCategory.orders;
    if (promo >= 1 && !fromPerson) return SmsCategory.promotions;
    if (fromPerson) return SmsCategory.personal;
    return SmsCategory.updates;
  }

  /// A real phone number (7 to 15 digits), not a short code or a sender name.
  static bool isPhoneNumber(String address) {
    final clean = address.replaceAll(RegExp(r'[\s\-().]'), '');
    return RegExp(r'^\+?\d{7,15}$').hasMatch(clean);
  }

  /// Indian DLT sender ids end in -P (promotional), -S (service), -T
  /// (transactional) or -G (government), for example `VM-AMAZON-P`.
  static String? dltSuffix(String address) =>
      RegExp(r'^[A-Z0-9]{2}-[A-Z0-9]{3,9}-([PSTG])$', caseSensitive: false).firstMatch(address.trim())?.group(1)?.toUpperCase();

  /// How strongly a message looks like an ad. 2 or more is a clear promotion.
  static int promoScore(String address, String lowerBody) {
    var score = _promo.allMatches(lowerBody).length;
    if (dltSuffix(address) == 'P') score += 2;
    return score;
  }

  static final _otpWord = RegExp(
    r'\b(otp|one[\s-]?time[\s-]?(password|passcode|pin|code)|verification code|verify code|security code|'
    r'auth(entication)? code|login code|sign[\s-]?in code|access code|confirmation code|passcode|2fa|'
    r'code is|is your code|is your .{0,20}code)\b',
  );
  static final _code = RegExp(r'\b(?=[a-z0-9-]*\d)[a-z0-9]{3,4}-?[a-z0-9]{1,4}\b');

  static final _couponCode = RegExp(r'\b(promo|coupon|discount|voucher|referral|gift)\s?code\b|\buse code\b');

  static bool _isOtp(String text) => _otpWord.hasMatch(text) && _code.hasMatch(text) && !_couponCode.hasMatch(text);

  static final _money = RegExp(r'(rs\.?|inr|₹|usd|\$)\s?[\d,]+(\.\d+)?');
  static final _txnWord = RegExp(
    r'\b(debited|credited|withdrawn|spent|paid|received|transferred|deposited|txn|transaction|'
    r'a/c|acct|account|upi|neft|imps|rtgs|avl\.? bal|available balance|card ending|refund(ed)?|emi)\b',
  );
  static final _strongTxn = RegExp(r'\b(debited|credited)\b');

  static bool _isBank(String text) => _strongTxn.hasMatch(text) || (_money.hasMatch(text) && _txnWord.hasMatch(text) && !_loanAd.hasMatch(text));

  static final _loanAd = RegExp(r'\b(pre-?approved|apply now|get (a )?loan|instant loan|loan up ?to)\b');

  static final _order = RegExp(
    r'\b(order(ed)?|shipped|dispatched|delivered|out for delivery|delivery|courier|tracking|track your|'
    r'awb|parcel|shipment|arriving|pnr|booking (id|confirmed)|ticket|boarding)\b',
  );

  static final _promo = RegExp(
    r'(\b(offer|offers|sale|discount|cashback|coupon|promo ?code|use code|deals?|free|win|won|winner|prize|'
    r'lucky|hurry|limited (time|period)|last day|ends (today|tonight)|shop now|buy now|order now|book now|'
    r'apply now|register now|grab|exclusive|best price|lowest price|recharge now|pre-?approved|loan|'
    r'congratulations|claim|unsubscribe|t ?& ?c|tnc|missed call|sms stop|stop to)\b|\d+\s?% ?off|\bflat \d+|\bup ?to \d+\s?%)',
  );
}
