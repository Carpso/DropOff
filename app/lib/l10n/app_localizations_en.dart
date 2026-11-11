// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DropOff Zambia';

  @override
  String get selectLanguage => 'App language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageNyanja => 'Nyanja (Chinyanja)';

  @override
  String get languageBemba => 'Bemba (Ichibemba)';

  @override
  String get languageTongaZambia => 'Tonga (Zambia) / Chitonga';

  @override
  String get languageLozi => 'Lozi (Silozi)';

  @override
  String get skipRideWarningTitle => 'Don\'t miss your pickup';

  @override
  String get skipRideWarningBody =>
      'If you miss your rider or don\'t hand over the parcel in time, the booking may be auto-canceled and a no-show strike recorded. 3 strikes in 14 days can pause new bookings.';

  @override
  String get bookingOnHoldTitle => 'Booking on hold';

  @override
  String get bookingOnHoldBody =>
      'Recent missed pickups put new bookings on hold. Contact DropOff support or ask ops to review your account.';

  @override
  String get depositRequiredTitle => 'Prepay for your parcel at booking';

  @override
  String get depositRequiredBody =>
      'Every parcel is paid in advance at booking. The app sends you a prepayment prompt for exactly this delivery (trip price + processing fee) before your rider is dispatched, and no rider ever handles your cash. If the booking is canceled before pickup, the unspent prepayment is automatically returned to your momo.';

  @override
  String get slotRequiredTitle => 'Choose a pickup slot';

  @override
  String get slotRequiredBody =>
      'Every parcel must be booked onto a Sweep slot (no untimed pickups).';

  @override
  String get cutoffWarning =>
      'Book before the slot cutoff to avoid moving to the next open slot.';

  @override
  String get handoverCodeWarning =>
      'Ask the recipient for their 4-digit DropOff code. Never enter a code the parcel owner hasn\'t shown you.';

  @override
  String get coverTosTitle => 'Parcel cover terms';

  @override
  String get coverTosBody =>
      'Optional cover is a quoted protection product, NOT automatic insurance. Limits, exclusions, eligibility, and evidence requirements apply. Cover is only active if DropOff confirms it under the applicable terms (legal/commercial sign-off required). By opting in you accept these terms.';

  @override
  String get coverAcceptTerms =>
      'I accept the cover terms (quoted, not insurance)';

  @override
  String get evidenceShare => 'Share evidence';

  @override
  String get bestSlot => 'Best slot for your area';

  @override
  String get savedRecipients => 'Saved recipients';

  @override
  String get pickRecipient => 'Pick saved recipient';

  @override
  String get saveRecipient => 'Save this recipient';

  @override
  String get recipientSaved => 'Recipient saved';

  @override
  String get quickRebook => 'Quick rebook';

  @override
  String get declaredValue => 'Declared value (ZMW)';

  @override
  String get parcelCover => 'Parcel cover (optional)';

  @override
  String get coverDisclaimer =>
      'Cover is an optional quoted protection product. Terms, limits and eligibility apply; it is not automatic insurance until confirmed.';

  @override
  String get riderStopTitle => 'How did the parcel move on?';

  @override
  String get riderPickedUp => 'Picked up from the seller';

  @override
  String get riderPickedUpSub => 'File it before leaving the stop';

  @override
  String get riderDepotDrop => 'Dropped at the depot branch';

  @override
  String get riderDepotDropSub =>
      'Camera photo marks the handover — no fare to enter';

  @override
  String get riderDoorDrop => 'Handed to the recipient (door)';

  @override
  String get riderDoorDropSub => 'Requires their 4-digit DropOff code';

  @override
  String get riderNotYet => 'Not yet — go back';

  @override
  String get riderPhotoRequired =>
      'A camera photo of the parcel is required — delivery is marked by camera capture.';

  @override
  String get riderDoorPhotoAdd => 'Add proof photo (required)';

  @override
  String get riderDoorPhotoAttached => 'Proof photo attached ✓';

  @override
  String get riderDoorPhotoRequired =>
      'Attach the camera photo of the handover to confirm.';
}
