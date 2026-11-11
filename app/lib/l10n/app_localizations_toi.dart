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
  String get selectLanguage => 'Mwaambo wa app';

  @override
  String get languageEnglish => 'Cingisi';

  @override
  String get languageNyanja => 'Cinyanja';

  @override
  String get languageBemba => 'Cibemba';

  @override
  String get languageTongaZambia => 'Chitonga (Zambia)';

  @override
  String get languageLozi => 'Silozi';

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
  String get depositRequiredTitle => 'Amupile parcel yanu pangu pa booking';

  @override
  String get depositRequiredBody =>
      'Cintu acimwi cipilikwa advance pa booking. App ilatumya prepayment prompt ya ulendo ooyo (trip price + processing fee) ucintu nitachitalatumwa rider, alimwi rider tachiimwe ca cash yanu. Mwekuti iko cancel before pickup, ndalama zitalibwi zibweleka ku momo yanu.';

  @override
  String get slotRequiredTitle => 'Amusale ciindi cakubwezegwa';

  @override
  String get slotRequiredBody =>
      'Cintu acimwi ceelede kubbukkiwa aciindi ca Sweep (tacili cakubwezegwa citajisi ciindi).';

  @override
  String get cutoffWarning =>
      'Amubbukke cutoff kaitanasika kutegwa mutaunki kuciindi citobela.';

  @override
  String get handoverCodeWarning =>
      'Amubuzye uutambula koodi ya DropOff ya manamba 4. Mutanjizyi koodi mwini cintu njatana kumutondezya.';

  @override
  String get coverTosTitle => 'Milawo yacikwabilizyo cacintu';

  @override
  String get coverTosBody =>
      'Cikwabilizyo ncakusala, tacinshuwalansi pe. Mipimo, milawo abumboni zilabeleka. Cilabeleka buyo DropOff yaakuzumina. Kwiinda mukusala, mulazumina milawo eeyi.';

  @override
  String get coverAcceptTerms =>
      'Ndazumina milawo yacikwabilizyo (tacinshuwalansi)';

  @override
  String get evidenceShare => 'Amwaabile bumboni';

  @override
  String get bestSlot => 'Ciindi cibotu mucooko canu';

  @override
  String get savedRecipients => 'Batambula babikkidwe';

  @override
  String get pickRecipient => 'Amusale uutambula uubikkidwe';

  @override
  String get saveRecipient => 'Amubikke uutambula ooyu';

  @override
  String get recipientSaved => 'Uutambula wabikkwa';

  @override
  String get quickRebook => 'Amubbukke alimwi cakufwambaana';

  @override
  String get declaredValue => 'Muulo waambidwe (ZMW)';

  @override
  String get parcelCover => 'Cikwabilizyo cacintu (kusala)';

  @override
  String get coverDisclaimer =>
      'Cikwabilizyo ncintu cakusala. Milawo amipimo ilabeleka; tacinshuwalansi pe kusikila cazuminwa.';

  @override
  String get riderStopTitle => 'Kodi cipakete caa endede zyuli?';

  @override
  String get riderPickedUp => 'Cpackete ca telwa kuli muntu uutuma';

  @override
  String get riderPickedUpSub => 'Lemba apo uli';

  @override
  String get riderDepotDrop => 'Cpackete ca siwa pa depot branch';

  @override
  String get riderDepotDropSub =>
      'Ciphongolo ca camera cisaamuna ku lata — takwaba ku nsonga zya muulo';

  @override
  String get riderDoorDrop => 'Cpackete ca peswa kuli muntu uwazula (munzi)';

  @override
  String get riderDoorDropSub => 'Kusyowa 4-digit DropOff code';

  @override
  String get riderNotYet => 'Pebe — weza';

  @override
  String get riderPhotoRequired =>
      'Ciphongolo ca camera ca cipakete cijisi — kufuma kwasya kuti kasamunwa a camera.';

  @override
  String get riderDoorPhotoAdd => 'Wongeya ciphongolo ca camera (cijisi)';

  @override
  String get riderDoorPhotoAttached => 'Ciphongolo ca camera cacizumwa ✓';

  @override
  String get riderDoorPhotoRequired =>
      'Kalipanze ciphongolo ca camera kuti azumiswe.';
}
