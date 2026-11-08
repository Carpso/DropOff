// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tonga (`toi`).
class AppLocalizationsToi extends AppLocalizations {
  AppLocalizationsToi([String locale = 'toi']) : super(locale);

  @override
  String get appTitle => 'DropOff Zambia';

  @override
  String get skipRideWarningTitle => 'Mutaphonyi kubwezegwa';

  @override
  String get skipRideWarningBody =>
      'Na mwaphonya rider naa mutapa cintu aciindi, kubbukka kulakonzya kumana alimwi no-show strike ilalembwa. Ma strike 3 mumazuba 14 alakonzya kulesya kubbukka kupya.';

  @override
  String get bookingOnHoldTitle => 'Kubbukka kwayimikizigwa';

  @override
  String get bookingOnHoldBody =>
      'Kuphonya kwakunembo kwayimikizya kubbukka kupya. Amwaambe ku DropOff support naa ops.';

  @override
  String get depositRequiredTitle => 'Deposit ilayandika rider katana kutumwa';

  @override
  String get depositRequiredBody =>
      'Bakubbukka ciindi cakusaanguna (pay-as-you-go) balayandika kuzumina deposit niini rider katana kutumwa. Bapulani tabayandiki. Deposit inookkala mu wallet yanu ya DropOff.';

  @override
  String get slotRequiredTitle => 'Amusale ciindi cakubwezegwa';

  @override
  String get slotRequiredBody =>
      'Cintu acimwi ceelede kubbukkiwa aciindi ca Sweep (tacili cakubwezegwa citajisi ciindi).';

  @override
  String get cutoffWarning =>
      'Amubbukke cutoff kaitanasika kutegwa mutaunki kuciindi citobela.';

  @override
  String get evidenceShare => 'Amwaabile bumboni';

  @override
  String get bestSlot => 'Ciindi cibotu mucooko canu';

  @override
  String get savedRecipients => 'Batambula babikkidwe';

  @override
  String get declaredValue => 'Muulo waambidwe (ZMW)';

  @override
  String get parcelCover => 'Cikwabilizyo cacintu (kusala)';

  @override
  String get coverDisclaimer =>
      'Cikwabilizyo ncintu cakusala. Milawo amipimo ilabeleka; tacinshuwalansi pe kusikila cazuminwa.';
}
