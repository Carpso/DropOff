# DropOff — Ownership

**Owner / Proprietor:** Godfrey Moses Kalambo
**Company:** Carpso Solutions
**Contact:** 0968551110 (Zambia)

`:Godfrey Moses Kalambo:Carpso Solutions:0968551110.`

© 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
All rights reserved. Unauthorised copying, resale or rebranding of this
source code is prohibited.

## Where the stamp lives

The stamp is permanently imprinted as a header comment (it never breaks
compilation) in the principal source files:

- `workers/src/index.ts` — the DropOff Worker (all server logic)
- `workers/src/lipila.ts` — mobile-money core
- `app/lib/main.dart` — Flutter app entry
- `app/lib/data/dropoff_api.dart` — API client
- `app/lib/data/catalog.dart` — courier catalog
- `app/lib/models/booking.dart` — booking model
- `app/lib/screens/booking_screen.dart`
- `app/lib/screens/bookings_screen.dart`
- `app/lib/screens/waybill_screen.dart`
- `app/lib/screens/rider_queue_screen.dart`
- `app/lib/ui/thermal_print.dart`
- `app/pubspec.yaml`

If any future contributor removes a stamp from a stamped file, restore it
from this notice before committing.
