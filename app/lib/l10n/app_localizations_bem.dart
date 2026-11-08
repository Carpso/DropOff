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
  String get depositRequiredTitle => 'Deposit ilefwaikwa ilyo rider talatumwa';

  @override
  String get depositRequiredBody =>
      'Ababukisha umuku wa kubalilapo (pay-as-you-go) balefwaikwa ukusuminisha deposit inono ilyo rider talatumwa. Abakwata plan tabafwaikwa. Deposit ikala mu wallet yenu iya DropOff.';

  @override
  String get slotRequiredTitle => 'Saleni inshita ya kupokwa';

  @override
  String get slotRequiredBody =>
      'Cila cipe cifwile cabukishiwa pa nshita ya Sweep (tapaba ukupokwa ukwabula nshita).';

  @override
  String get cutoffWarning =>
      'Bukisheni ilyo cutoff tailafika pakuti mwilaya ku nshita ikakonkapo.';

  @override
  String get evidenceShare => 'Akeni ubunte';

  @override
  String get bestSlot => 'Inshita isuma mu ncende yenu';

  @override
  String get savedRecipients => 'Abapokelela abasungilwe';

  @override
  String get declaredValue => 'Umutengo uwalumbulwa (ZMW)';

  @override
  String get parcelCover => 'Ubuchingo bwa cipe (ukusalapo)';

  @override
  String get coverDisclaimer =>
      'Ubuchingo bupepala ubwakusalapo. Amafunde na mipaka filabomba; te inshuwalansi iyine mpaka yashininkishiwa.';
}
