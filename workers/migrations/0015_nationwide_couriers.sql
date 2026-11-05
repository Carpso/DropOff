-- 0015: nationwide intercity courier coverage — ZICTA-licensed operators not
-- previously in the directory. Sources: ZICTA licensed postal & courier
-- operators public notice (Sep 2021) + current official sites. Rates remain
-- quote_on_request unless a partner confirms them in the ratebook.
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Peshi Delivery', 'Lusaka', 'Kwacha Square Mall, Lake Rd', NULL, NULL,
  'https://peshidelivery.com/zm/', 'quote_on_request',
  'Zambian-owned nationwide courier; Intercity desk at Intercity Bus Terminus, Lusaka. +260 772 827 180 / +260 765 654 448 · support@peshidelivery.com')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Peshi Delivery' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Kingsway Couriers', 'Lusaka', 'Oasis Mall Shop 77, opp Intercity Bus Terminus', NULL, NULL,
  'https://www.kingswaycourier.com/', 'quote_on_request',
  'Lusaka / Ndola / Kitwe / Livingstone + beyond. +260 977 652040 · kingswaycourierltd@gmail.com')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Kingsway Couriers' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Power Tools Couriers', 'Lusaka', 'Nationwide express courier network', NULL, NULL,
  'https://powertoolscouriers.com/', 'quote_on_request',
  'Zambian-owned since 1996 (BEM Motors Group). 2-day delivery all 10 provinces, nationwide bus courier bookings.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Power Tools Couriers' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Walter Genius', 'Lusaka', 'Mills House, Lunsemfwa Rd, Kalundu', NULL, NULL,
  'https://www.waltergenius.com/', 'quote_on_request',
  'Domestic + international, road & air freight. +260 211 844044 · info@waltergenius.com')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Walter Genius' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Danal Express Courier Service', 'Lusaka', 'Stand 21, Dedan Kimathi Intercity Bus Terminus', NULL, NULL,
  NULL, 'quote_on_request',
  'Bus-parcel intercity courier from the Intercity Bus Terminus, Dedan Kimathi Rd. ZICTA licensed courier (domestic).')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Danal Express Courier Service' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Circuit Express', 'Chipata', 'R204 off Kafula Rd, near Teena Guest House, Kapata', NULL, NULL,
  NULL, 'quote_on_request',
  'Chipata (Eastern Province) licensed domestic courier — covers Chipata / Petauke / Nyimba / Katete routes.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Circuit Express' AND city='Chipata');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'United Bus Company (2020) Courier', 'Lusaka', 'Plot F377A, Kudu Rd, Kabulonga', NULL, NULL,
  NULL, 'quote_on_request',
  'Bus-parcel intercity courier (Kabulonga). ZICTA-licensed international & domestic courier.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='United Bus Company (2020) Courier' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'FedEx Express Zambia', 'Lusaka', 'Plot 1321, Enock Kavu Rd, Lusaka', NULL, NULL,
  'https://www.fedex.com/zm', 'quote_on_request',
  'International + domestic express (Zambia). +260 216 221 411. Quote via fedex.com or counter.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='FedEx Express Zambia' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Verinet', 'Ndola', 'Plot 11354, Mitengo, Ndola', NULL, NULL,
  NULL, 'quote_on_request',
  'Ndola (Copperbelt) licensed domestic courier — intercity Copperbelt coverage.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Verinet' AND city='Ndola');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Tredstone General Dealers', 'Ndola', 'Plot 9694, Kansenshi-Mitebgo Rd, Mitengo', NULL, NULL,
  NULL, 'quote_on_request',
  'Ndola (Copperbelt) licensed local courier — Copperbelt towns.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Tredstone General Dealers' AND city='Ndola');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Joseph and Mary Courier Logistics', 'Lusaka', 'No. 11965, Ngwerere Rd, Chelstone', NULL, NULL,
  NULL, 'quote_on_request',
  'Chelstone (Lusaka East) — international & domestic courier, ZICTA licensed.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Joseph and Mary Courier Logistics' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Tutume Worldwide Zambia', 'Lusaka', '8 Lunzua Rd, Unit 1, Lusaka', NULL, NULL,
  NULL, 'quote_on_request',
  'ZICTA-licensed domestic courier (Lunzua Rd area).')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Tutume Worldwide Zambia' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Diandian Zambia Logistics', 'Lusaka', 'Plot 9476, off Kafue Rd, Makeni', NULL, NULL,
  NULL, 'quote_on_request',
  'Makeni / Kafue Rd corridor — international & domestic courier.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Diandian Zambia Logistics' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'STC Courier and Logistics', 'Lusaka', 'Plot 1607, Mwauko St, Chelstone', NULL, NULL,
  NULL, 'quote_on_request',
  'Chelstone licensed domestic courier.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='STC Courier and Logistics' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Once Picked Express', 'Lusaka', 'Plot 5065, Sibweni Rd, Northmead', NULL, NULL,
  NULL, 'quote_on_request',
  'Northmead licensed domestic courier.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Once Picked Express' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Ultimate Ingenuity Zambia', 'Lusaka', 'No. 7, Chitemwiko Rd, Kabulonga', NULL, NULL,
  NULL, 'quote_on_request',
  'Kabulonga licensed domestic courier.')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Ultimate Ingenuity Zambia' AND city='Lusaka');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note)
SELECT * FROM (SELECT 'Links Express Logistics', 'Lusaka', 'Unit 4, Selby Taylor Complex, Roan Rd, Kabulonga', NULL, NULL,
  'https://www.linksexpress.co.zm/', 'quote_on_request',
  'Kabulonga — international & domestic courier; UK/China/USA receiving hubs; +260 975 908 835 · u@linksexpress.co.zm')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name='Links Express Logistics' AND city='Lusaka');
