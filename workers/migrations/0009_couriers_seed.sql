-- 0009: seed the live chargebook couriers researched from ZICTA-licensed
-- operators (Sept-2021 public notice) + current websites. Logos are the
-- operators' own hosted assets; the app falls back to initials when null.

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT
  'Zampost (Zambia Post)' AS n, 'Lusaka' AS c, 'Zampost Provident House (Cairo Road)' AS d,
  -15.4266 AS la, 28.2792 AS ln, NULL AS w, NULL AS lg
) WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = n AND city = c AND depot_name = d);
INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Zampost (Zambia Post)', 'Kitwe', 'Zampost Kitwe Main Office', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Zampost (Zambia Post)' AND city = 'Kitwe' AND depot_name = 'Zampost Kitwe Main Office');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'PostDotNet (PDN)', 'Lusaka', 'PDN Service Centre', NULL, NULL,
  'https://postdotnet.co.zm', 'https://postdotnet.co.zm/wp-content/uploads/2025/07/cropped-WhatsApp_Image_2025-07-23_at_2.54.16_PM-removebg-preview.png')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'PostDotNet (PDN)' AND city = 'Lusaka' AND depot_name = 'PDN Service Centre');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'PostDotNet (PDN)', 'Livingstone', 'PDN Livingstone Outlet', NULL, NULL,
  'https://postdotnet.co.zm', 'https://postdotnet.co.zm/wp-content/uploads/2025/07/cropped-WhatsApp_Image_2025-07-23_at_2.54.16_PM-removebg-preview.png')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'PostDotNet (PDN)' AND city = 'Livingstone');
INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'PostDotNet (PDN)', 'Ndola', 'PDN Mukuba Mall Outlet', NULL, NULL,
  'https://postdotnet.co.zm', 'https://postdotnet.co.zm/wp-content/uploads/2025/07/cropped-WhatsApp_Image_2025-07-23_at_2.54.16_PM-removebg-preview.png')
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'PostDotNet (PDN)' AND city = 'Ndola');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Gavic Express', 'Lusaka', 'Indeco House (Cairo Road)', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Gavic Express' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'One World Freight (UPS contractor)', 'Lusaka', 'Rhodes Park Depot', NULL, NULL,
  'https://oneworld.co.zm', NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'One World Freight (UPS contractor)' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'DHL Express ServicePoint', 'Lusaka', 'Enock Kavu Road ServicePoint', NULL, NULL,
  'https://www.dhl.com/zm-en/home.html', NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'DHL Express ServicePoint' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Peshi Delivery', 'Lusaka', 'Kwacha Square Mall', NULL, NULL,
  'https://peshidelivery.com/zm/', NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Peshi Delivery' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Eastlight Logistics', 'Lusaka', 'DGM Complex (Mukwa Road)', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Eastlight Logistics' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Shipflex Express', 'Lusaka', 'Greenlane (Kabulonga)', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Shipflex Express' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'MacSpeedy''s Messengers', 'Lusaka', 'Provident Street (Rhodes Park)', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'MacSpeedy''s Messengers' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Amezam', 'Lusaka', 'Kafue Road Depot', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Amezam' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Mazhandu Courier', 'Lusaka', 'Mazhandu Counter (InterCity Bus Station)', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Mazhandu Courier' AND city = 'Lusaka');

INSERT INTO couriers (name, city, depot_name, lat, lng, website, logo_url)
SELECT * FROM (SELECT 'Shalom Bus Parcel', 'Lusaka', 'Shalom Terminus Counter', NULL, NULL, NULL, NULL)
WHERE NOT EXISTS (SELECT 1 FROM couriers WHERE name = 'Shalom Bus Parcel' AND city = 'Lusaka');

-- logos for the already-seeded partners with known hosted assets
UPDATE couriers SET logo_url = 'https://www.mercury.co.zm/wp-content/uploads/2018/10/logo-300.png'
WHERE name LIKE '%Mercury%' AND logo_url IS NULL;
UPDATE couriers SET logo_url = 'https://icypeed.com/wp-content/uploads/2023/08/wp-cargo-logo-format-for-icypeed-png.png'
WHERE name LIKE '%Icypeed%' AND logo_url IS NULL;
UPDATE couriers SET website = 'https://icypeed.com' WHERE name LIKE '%Icypeed%' AND (website IS NULL OR website = '');
