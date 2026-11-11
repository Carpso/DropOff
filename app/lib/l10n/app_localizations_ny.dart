// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Nyanja Chewa Chichewa (`ny`).
class AppLocalizationsNy extends AppLocalizations {
  AppLocalizationsNy([String locale = 'ny']) : super(locale);

  @override
  String get appTitle => 'DropOff Zambia';

  @override
  String get selectLanguage => 'Chilankhulo cha app';

  @override
  String get languageEnglish => 'Chingerezi';

  @override
  String get languageNyanja => 'Chinyanja';

  @override
  String get languageBemba => 'Chibemba';

  @override
  String get languageTongaZambia => 'Chitonga (Zambia)';

  @override
  String get languageLozi => 'Silozi';

  @override
  String get skipRideWarningTitle => 'Musaphonye kulandidwa';

  @override
  String get skipRideWarningBody =>
      'Ngati simupezeka kapena simupereka katundu pa nthawi, ulendo ungathetsedwe ndipo no-show strike ilembedwa. Ma strike 3 pa masiku 14 angayimitse kubukanso.';

  @override
  String get bookingOnHoldTitle => 'Kubukitsa kwayimitsidwa';

  @override
  String get bookingOnHoldBody =>
      'Maulendo ophonya posachedwa ayimitsa kubukitsa kwatsopano. Lumikizanani ndi DropOff support kapena ops.';

  @override
  String get depositRequiredTitle => 'Lipirani parcel yanu poyamba (advance)';

  @override
  String get depositRequiredBody =>
      'Parcel iliyonse imalipiridwa in advance pa book. App imatumiza prepayment prompt ya ulendo uu (trip price + processing fee) musanatumizidwe rider, ndipo rider asan\'akhudze ndi cash yanu. Ngati ulendo uthathetsedwa musanadze kulandidwa, ndalama yotsalayo ibwezeredwa ku momo yanu.';

  @override
  String get slotRequiredTitle => 'Sankhani nthawi yolandidwira';

  @override
  String get slotRequiredBody =>
      'Katundu aliyense ayenera kubukitsidwa pa nthawi ya Sweep (palibe yolandidwira yopanda nthawi).';

  @override
  String get cutoffWarning =>
      'Bukitsani nthawi yomaliza isanathe kuti musaike ku nthawi yotsatira.';

  @override
  String get handoverCodeWarning =>
      'Funsani wolandira nambala ya 4 ya DropOff. Musalowetse nambala imene mwini katundu sanakuonetseni.';

  @override
  String get coverTosTitle => 'Malamulo a chitetezo cha katundu';

  @override
  String get coverTosBody =>
      'Chitetezo ndichosankha ndipo si inshuwalansi yokha. Malire, malamulo ndi umboni zimagwira ntchito. Chitetezo chimagwira pokhapokha DropOff itavomereza. Mwa kusankha, mukuvomereza malamulowa.';

  @override
  String get coverAcceptTerms =>
      'Ndikuvomereza malamulo a chitetezo (si inshuwalansi)';

  @override
  String get evidenceShare => 'Gawani umboni';

  @override
  String get bestSlot => 'Nthawi yabwino m\'dera lanu';

  @override
  String get savedRecipients => 'Olandira osungidwa';

  @override
  String get pickRecipient => 'Sankhani wolandira wosungidwa';

  @override
  String get saveRecipient => 'Sungani wolandira uyu';

  @override
  String get recipientSaved => 'Wolandira wasungidwa';

  @override
  String get quickRebook => 'Bukitsaninso mwachangu';

  @override
  String get declaredValue => 'Mtengo wolengezedwa (ZMW)';

  @override
  String get parcelCover => 'Chitetezo cha katundu (posankha)';

  @override
  String get coverDisclaimer =>
      'Chitetezo ndi chinthu chosankha. Malamulo ndi malire amagwira ntchito; si inshuwalansi yokha mpaka itatsimikizidwa.';

  @override
  String get riderStopTitle => 'Kodi katundu anapitira bwanji?';

  @override
  String get riderPickedUp => 'Watengedwa kwa wotumiza';

  @override
  String get riderPickedUpSub => 'Lemba musanachoke pompano';

  @override
  String get riderDepotDrop => 'Wasiyidwa pa depot branch';

  @override
  String get riderDepotDropSub =>
      'Chithunzi cha kamera chimasonyeza kusamutsidwa — palibe cha mtengo cholemba';

  @override
  String get riderDoorDrop => 'Waperekedwa kwa wolandira (pakhomo)';

  @override
  String get riderDoorDropSub => 'Amafunikira DropOff code ya manambala 4';

  @override
  String get riderNotYet => 'Ayi pano — bwererani';

  @override
  String get riderPhotoRequired =>
      'Chithunzi cha kamera cha katundu chikufunika — kusamutsidwa kumawonetsedwa ndi kamera.';

  @override
  String get riderDoorPhotoAdd => 'Yikani chithunzi cha umboni (chofunikira)';

  @override
  String get riderDoorPhotoAttached => 'Chithunzi cha umboni chayikidwa ✓';

  @override
  String get riderDoorPhotoRequired =>
      'Yikani chithunzi cha kamera cha kusamutsidwa kuti mutsimikizire.';
}
