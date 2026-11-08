// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Lozi (`loz`).
class AppLocalizationsLoz extends AppLocalizations {
  AppLocalizationsLoz([String locale = 'loz']) : super(locale);

  @override
  String get appTitle => 'DropOff Zambia';

  @override
  String get skipRideWarningTitle => 'Musike mwa phonya kunangwa';

  @override
  String get skipRideWarningBody =>
      'Haiba mu phonya rider kapa hamufa sika ka nako, peeletso ikona kufela mi no-show strike i ng\'olwa. Li strike ze 3 mwa mazazi 14 likona ku yemisa ku beela hape.';

  @override
  String get bookingOnHoldTitle => 'Ku beela ku yemi';

  @override
  String get bookingOnHoldBody =>
      'Mi phonyeho ya kwa nyuma i yemisize ku beela kusha. Amu bulelisane ni DropOff support kapa ops.';

  @override
  String get depositRequiredTitle =>
      'Deposit i ya tokwa pili rider a sika ku romelwa';

  @override
  String get depositRequiredBody =>
      'Babeela lwa pili (pay-as-you-go) ba tokwa ku lumela deposit ye nyinyani pili rider a sika ku romelwa. Ba plan ha ba tokwi. Deposit i sala mwa wallet ya mina ya DropOff.';

  @override
  String get slotRequiredTitle => 'Amu kete nako ya kunangwa';

  @override
  String get slotRequiredBody =>
      'Sika ni sika si swanela ku beelwa ka nako ya Sweep (ha kuna kunangwa kwa ku se na nako).';

  @override
  String get cutoffWarning =>
      'Amu beele pili cutoff i sika fita ku se ye kwa nako ye tatama.';

  @override
  String get evidenceShare => 'Abelelana ka bupaki';

  @override
  String get bestSlot => 'Nako ye nde mwa sibaka sa mina';

  @override
  String get savedRecipients => 'Baamuheli ba babulukilwe';

  @override
  String get declaredValue => 'Teko ye bizizwe (ZMW)';

  @override
  String get parcelCover => 'Sikwalikanyi sa sika (ku keta)';

  @override
  String get coverDisclaimer =>
      'Sikwalikanyi ki sika sa ku keta. Milao ni mikwakwa i sebeza; ha si inshuwalansi kono ha i sa tii ku lumelwa.';
}
