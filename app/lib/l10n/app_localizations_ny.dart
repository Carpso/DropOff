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
  String get depositRequiredTitle => 'Deposit ikufunika musanatumizidwe rider';

  @override
  String get depositRequiredBody =>
      'Obukitsa koyamba (pay-as-you-go) amafunika kuvomereza deposit yaing\'ono musanatumizidwe rider. Olembetsa satenga mbali. Deposit imakhala mu wallet yanu ya DropOff.';

  @override
  String get slotRequiredTitle => 'Sankhani nthawi yolandidwira';

  @override
  String get slotRequiredBody =>
      'Katundu aliyense ayenera kubukitsidwa pa nthawi ya Sweep (palibe yolandidwira yopanda nthawi).';

  @override
  String get cutoffWarning =>
      'Bukitsani nthawi yomaliza isanathe kuti musaike ku nthawi yotsatira.';

  @override
  String get evidenceShare => 'Gawani umboni';

  @override
  String get bestSlot => 'Nthawi yabwino m\'dera lanu';

  @override
  String get savedRecipients => 'Olandira osungidwa';

  @override
  String get declaredValue => 'Mtengo wolengezedwa (ZMW)';

  @override
  String get parcelCover => 'Chitetezo cha katundu (posankha)';

  @override
  String get coverDisclaimer =>
      'Chitetezo ndi chinthu chosankha. Malamulo ndi malire amagwira ntchito; si inshuwalansi yokha mpaka itatsimikizidwa.';
}
