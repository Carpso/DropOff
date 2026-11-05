-- 0011: Rovert Logistics — SA⇄Zambia freight/parcel partner (2× weekly, door-to-door).
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note, logo_url)
SELECT * FROM (SELECT
  'Rovert Logistics' AS n, 'Lusaka' AS c, 'Rovert Lusaka office (call +260 572307906)' AS d,
  -15.4040 AS la, 28.3326 AS ln,
  'https://rovertlogistics.co.za' AS w,
  'quote_on_request' AS ps,
  'SA⇄Zambia consignment courier (e-comm/Takealot → door-to-door, 2× weekly), SA→ZM freight forwarding with customs clearing. No public price card — all fares quote-based; counter price recorded before dispatch. Phones: Zambia +260 572307906 | SA +27 767360695 | enquiries@rovertlogistics.co.za (07:00–17:00 CAT). SA HQ: Building F, St Andrews Office Park, Meadowbrook Ln, Epsom Downs, Sandton 2152. Not a walk-in domestic depot network — book as SA-leg partner.' AS nt,
  NULL AS lg
) WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Rovert Logistics' AND city = 'Lusaka');
