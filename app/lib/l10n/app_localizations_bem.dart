// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bemba (`bem`).
class AppLocalizationsBem extends AppLocalizations {
  AppLocalizationsBem([String locale = 'bem']) : super(locale);

  @override
  String get appTitle => 'DropOff Zambia';

  @override
  String get selectLanguage => 'Ululimi lwa app';

  @override
  String get languageEnglish => 'Icingeleshi';

  @override
  String get languageNyanja => 'Icinyanja';

  @override
  String get languageBemba => 'Ichibemba';

  @override
  String get languageTongaZambia => 'Chitonga (Zambia)';

  @override
  String get languageLozi => 'Silozi';

  @override
  String get skipRideWarningTitle => 'Mwilacelela ukupokwa';

  @override
  String get skipRideWarningBody =>
      'Nga mwacelela rider nangu tamwapele ifipe pa nshita, booking kuti yapwa kabili no-show strike kuti yalembwa. Ama strike 3 mu nshiku 14 kuti yalesha ukubukisha.';

  @override
  String get bookingOnHoldTitle => 'Ukubukisha kwaleshiwa';

  @override
  String get bookingOnHoldBody =>
      'Ukuphonya ukwakunuma kwalesha ukubukisha ukupya. Landa na DropOff support nangu ops.';

  @override
  String get depositRequiredTitle => 'Lipeni parcel pari kusule na booking';

  @override
  String get depositRequiredBody =>
      'Cila cipe cilipilwa advance pe booking. App ituma prepayment prompt ya ulendo uyu (trip price + processing fee) ilyo rider talatumwa, kabili rider takwata cash yenu. Nga booking yaleshiwa ilyo shipping naitwalwa, indalama mishikile isubila ku momo yenu.';

  @override
  String get slotRequiredTitle => 'Saleni inshita ya kupokwa';

  @override
  String get slotRequiredBody =>
      'Cila cipe cifwile cabukishiwa pa nshita ya Sweep (tapaba ukupokwa ukwabula nshita).';

  @override
  String get cutoffWarning =>
      'Bukisheni ilyo cutoff tailafika pakuti mwilaya ku nshita ikakonkapo.';

  @override
  String get handoverCodeWarning =>
      'Ipusheni uupokelela koodi ya DropOff iya manambala 4. Mwilalemba koodi uyo umwine wa cipe tashimikumwesha.';

  @override
  String get coverTosTitle => 'Amafunde ya buchingo bwa cipe';

  @override
  String get coverTosBody =>
      'Ubuchingo bupepala ubwakusalapo, te inshuwalansi iyine. Imipaka, amafunde na bunte filabomba. Bucitika fye nga DropOff yasuminisha. Nga mwasalapo, mwalisumina aya mafunde.';

  @override
  String get coverAcceptTerms =>
      'Nasumina amafunde ya buchingo (te inshuwalansi)';

  @override
  String get evidenceShare => 'Akeni ubunte';

  @override
  String get bestSlot => 'Inshita isuma mu ncende yenu';

  @override
  String get savedRecipients => 'Abapokelela abasungilwe';

  @override
  String get pickRecipient => 'Saleni uupokelela uwasungilwe';

  @override
  String get saveRecipient => 'Sungeni uyu uupokelela';

  @override
  String get recipientSaved => 'Uupokelela asungilwe';

  @override
  String get quickRebook => 'Bukisheni bwangu na kabili';

  @override
  String get declaredValue => 'Umutengo uwalumbulwa (ZMW)';

  @override
  String get parcelCover => 'Ubuchingo bwa cipe (ukusalapo)';

  @override
  String get coverDisclaimer =>
      'Ubuchingo bupepala ubwakusalapo. Amafunde na mipaka filabomba; te inshuwalansi iyine mpaka yashininkishiwa.';
}
