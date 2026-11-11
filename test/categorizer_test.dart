import 'package:flutter_test/flutter_test.dart';
import 'package:sift/sms/categorizer.dart';

SmsCategory cat(String from, String body) => SmsCategorizer.categorize(from, body);

void main() {
  group('OTP', () {
    test('bank OTP', () {
      expect(cat('AX-HDFCBK-S', '482913 is your OTP for txn of Rs 500. Do not share it with anyone.'), SmsCategory.otp);
    });
    test('login code', () {
      expect(cat('JM-SWIGGY', 'Your verification code is 7731. It expires in 10 minutes.'), SmsCategory.otp);
    });
    test('G- style code', () {
      expect(cat('22000', 'G-482913 is your Google verification code.'), SmsCategory.otp);
    });
    test('promo code is not an OTP', () {
      expect(cat('VM-MYNTRA-P', 'Use code SAVE50 for 50% off on your next order! T&C apply'), SmsCategory.promotions);
    });
  });

  group('Bank', () {
    test('debit alert', () {
      expect(
        cat('AD-SBIINB-S', 'Your A/c XX1234 is debited for Rs.1,250.00 on 10-11-26 by UPI ref 6312. Avl Bal Rs 8,402'),
        SmsCategory.bank,
      );
    });
    test('credit alert', () {
      expect(cat('BZ-ICICIT', 'INR 25,000.00 credited to your account XX9012 by NEFT.'), SmsCategory.bank);
    });
    test('loan ad is a promotion, not bank', () {
      expect(
        cat('VK-HDFCBK-P', 'Congratulations! You have a pre-approved personal loan of Rs 5,00,000. Apply now.'),
        SmsCategory.promotions,
      );
    });
  });

  group('Orders', () {
    test('shipped', () {
      expect(cat('VM-AMAZON-S', 'Your order #402-11 has been shipped and is arriving Friday. Track: amzn.in/x'), SmsCategory.orders);
    });
    test('out for delivery', () {
      expect(cat('JD-DELHVY', 'Your parcel AWB 88213 is out for delivery today.'), SmsCategory.orders);
    });
    test('order-now ad is a promotion', () {
      expect(cat('JD-ZOMATO', 'Hungry? Order now and get flat 100 off. Hurry!'), SmsCategory.promotions);
    });
  });

  group('Promotions', () {
    test('DLT -P sender', () {
      expect(cat('VM-JIOMRT-P', 'Weekend groceries are here.'), SmsCategory.promotions);
    });
    test('sale keywords', () {
      expect(cat('AX-FLPKRT', 'Big Billion Days sale! Up to 80% off on phones.'), SmsCategory.promotions);
    });
    test('one weak word from a person stays personal', () {
      expect(cat('+91 98765 43210', 'Are you free tonight?'), SmsCategory.personal);
    });
    test('spammy number with many promo words', () {
      expect(cat('+919876543210', 'Congratulations! You won a prize. Claim now, limited time offer'), SmsCategory.promotions);
    });
  });

  group('Personal and updates', () {
    test('phone number', () {
      expect(cat('+91 98765 43210', 'Reached home, call you later'), SmsCategory.personal);
    });
    test('company notice', () {
      expect(cat('JK-AIRTEL', 'Your data pack will expire on 12 Nov.'), SmsCategory.updates);
    });
    test('short code is not a person', () {
      expect(SmsCategorizer.isPhoneNumber('57575'), isFalse);
      expect(SmsCategorizer.isPhoneNumber('(415) 555-0132'), isTrue);
    });
  });

  test('DLT suffix', () {
    expect(SmsCategorizer.dltSuffix('VM-AMAZON-P'), 'P');
    expect(SmsCategorizer.dltSuffix('ax-hdfcbk-s'), 'S');
    expect(SmsCategorizer.dltSuffix('JD-DELHVY'), isNull);
  });
}
