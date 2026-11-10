import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bem.dart';
import 'app_localizations_en.dart';
import 'app_localizations_loz.dart';
import 'app_localizations_ny.dart';
import 'app_localizations_toi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ny'),
    Locale('bem'),
    Locale('toi'),
    Locale('loz')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DropOff Zambia'**
  String get appTitle;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get selectLanguage;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageNyanja.
  ///
  /// In en, this message translates to:
  /// **'Nyanja (Chinyanja)'**
  String get languageNyanja;

  /// No description provided for @languageBemba.
  ///
  /// In en, this message translates to:
  /// **'Bemba (Ichibemba)'**
  String get languageBemba;

  /// No description provided for @languageTongaZambia.
  ///
  /// In en, this message translates to:
  /// **'Tonga (Zambia) / Chitonga'**
  String get languageTongaZambia;

  /// No description provided for @languageLozi.
  ///
  /// In en, this message translates to:
  /// **'Lozi (Silozi)'**
  String get languageLozi;

  /// No description provided for @skipRideWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Don\'t miss your pickup'**
  String get skipRideWarningTitle;

  /// No description provided for @skipRideWarningBody.
  ///
  /// In en, this message translates to:
  /// **'If you miss your rider or don\'t hand over the parcel in time, the booking may be auto-canceled and a no-show strike recorded. 3 strikes in 14 days can pause new bookings.'**
  String get skipRideWarningBody;

  /// No description provided for @bookingOnHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking on hold'**
  String get bookingOnHoldTitle;

  /// No description provided for @bookingOnHoldBody.
  ///
  /// In en, this message translates to:
  /// **'Recent missed pickups put new bookings on hold. Contact DropOff support or ask ops to review your account.'**
  String get bookingOnHoldBody;

  /// No description provided for @depositRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepay for your parcel at booking'**
  String get depositRequiredTitle;

  /// No description provided for @depositRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Every parcel is paid in advance at booking. The app sends you a prepayment prompt for exactly this delivery (trip price + processing fee) before your rider is dispatched, and no rider ever handles your cash. If the booking is canceled before pickup, the unspent prepayment is automatically returned to your momo.'**
  String get depositRequiredBody;

  /// No description provided for @slotRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a pickup slot'**
  String get slotRequiredTitle;

  /// No description provided for @slotRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Every parcel must be booked onto a Sweep slot (no untimed pickups).'**
  String get slotRequiredBody;

  /// No description provided for @cutoffWarning.
  ///
  /// In en, this message translates to:
  /// **'Book before the slot cutoff to avoid moving to the next open slot.'**
  String get cutoffWarning;

  /// No description provided for @handoverCodeWarning.
  ///
  /// In en, this message translates to:
  /// **'Ask the recipient for their 4-digit DropOff code. Never enter a code the parcel owner hasn\'t shown you.'**
  String get handoverCodeWarning;

  /// No description provided for @coverTosTitle.
  ///
  /// In en, this message translates to:
  /// **'Parcel cover terms'**
  String get coverTosTitle;

  /// No description provided for @coverTosBody.
  ///
  /// In en, this message translates to:
  /// **'Optional cover is a quoted protection product, NOT automatic insurance. Limits, exclusions, eligibility, and evidence requirements apply. Cover is only active if DropOff confirms it under the applicable terms (legal/commercial sign-off required). By opting in you accept these terms.'**
  String get coverTosBody;

  /// No description provided for @coverAcceptTerms.
  ///
  /// In en, this message translates to:
  /// **'I accept the cover terms (quoted, not insurance)'**
  String get coverAcceptTerms;

  /// No description provided for @evidenceShare.
  ///
  /// In en, this message translates to:
  /// **'Share evidence'**
  String get evidenceShare;

  /// No description provided for @bestSlot.
  ///
  /// In en, this message translates to:
  /// **'Best slot for your area'**
  String get bestSlot;

  /// No description provided for @savedRecipients.
  ///
  /// In en, this message translates to:
  /// **'Saved recipients'**
  String get savedRecipients;

  /// No description provided for @pickRecipient.
  ///
  /// In en, this message translates to:
  /// **'Pick saved recipient'**
  String get pickRecipient;

  /// No description provided for @saveRecipient.
  ///
  /// In en, this message translates to:
  /// **'Save this recipient'**
  String get saveRecipient;

  /// No description provided for @recipientSaved.
  ///
  /// In en, this message translates to:
  /// **'Recipient saved'**
  String get recipientSaved;

  /// No description provided for @quickRebook.
  ///
  /// In en, this message translates to:
  /// **'Quick rebook'**
  String get quickRebook;

  /// No description provided for @declaredValue.
  ///
  /// In en, this message translates to:
  /// **'Declared value (ZMW)'**
  String get declaredValue;

  /// No description provided for @parcelCover.
  ///
  /// In en, this message translates to:
  /// **'Parcel cover (optional)'**
  String get parcelCover;

  /// No description provided for @coverDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Cover is an optional quoted protection product. Terms, limits and eligibility apply; it is not automatic insurance until confirmed.'**
  String get coverDisclaimer;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bem', 'en', 'loz', 'ny', 'toi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bem':
      return AppLocalizationsBem();
    case 'en':
      return AppLocalizationsEn();
    case 'loz':
      return AppLocalizationsLoz();
    case 'ny':
      return AppLocalizationsNy();
    case 'toi':
      return AppLocalizationsToi();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
