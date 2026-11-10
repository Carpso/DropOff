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
  String get selectLanguage => 'Puo ya app';

  @override
  String get languageEnglish => 'Sikuwa';

  @override
  String get languageNyanja => 'Chinyanja';

  @override
  String get languageBemba => 'Chibemba';

  @override
  String get languageTongaZambia => 'Chitonga (Zambia)';

  @override
  String get languageLozi => 'Silozi';

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
  String get depositRequiredTitle => 'Kafate sika sa hae mwa booking';

  @override
  String get depositRequiredBody =>
      'Bakafatete ka moka ba kafwa advance mwa booking. App i romela prepayment prompt ya safari ye (trip price + processing fee) pili rider a sa romelwe, mina rider ha a nga cash ya mina. Ha booking i ka cancelwa pili pickup, chelete ye salilwe i buswa ku momo ya mina.';

  @override
  String get slotRequiredTitle => 'Amu kete nako ya kunangwa';

  @override
  String get slotRequiredBody =>
      'Sika ni sika si swanela ku beelwa ka nako ya Sweep (ha kuna kunangwa kwa ku se na nako).';

  @override
  String get cutoffWarning =>
      'Amu beele pili cutoff i sika fita ku se ye kwa nako ye tatama.';

  @override
  String get handoverCodeWarning =>
      'Amu buze muamuheli khoutu ya DropOff ya linomolo ze 4. Musike mwa kenya khoutu ye mu si ka boniswa ki mong\'a sika.';

  @override
  String get coverTosTitle => 'Milao ya sikwalikanyi sa sika';

  @override
  String get coverTosBody =>
      'Sikwalikanyi ki sa ku keta, ha si inshuwalansi. Mikwakwa, milao ni bupaki li ya sebeza. Si sebeza feela ha DropOff i ka si lumela. Ka ku keta, mu lumela milao ye.';

  @override
  String get coverAcceptTerms =>
      'Na lumela milao ya sikwalikanyi (ha si inshuwalansi)';

  @override
  String get evidenceShare => 'Abelelana ka bupaki';

  @override
  String get bestSlot => 'Nako ye nde mwa sibaka sa mina';

  @override
  String get savedRecipients => 'Baamuheli ba babulukilwe';

  @override
  String get pickRecipient => 'Keta muamuheli ya babulukilwe';

  @override
  String get saveRecipient => 'Buluka muamuheli yo';

  @override
  String get recipientSaved => 'Muamuheli u bulukilwe';

  @override
  String get quickRebook => 'Beela hape ka kapili';

  @override
  String get declaredValue => 'Teko ye bizizwe (ZMW)';

  @override
  String get parcelCover => 'Sikwalikanyi sa sika (ku keta)';

  @override
  String get coverDisclaimer =>
      'Sikwalikanyi ki sika sa ku keta. Milao ni mikwakwa i sebeza; ha si inshuwalansi kono ha i sa tii ku lumelwa.';
}
