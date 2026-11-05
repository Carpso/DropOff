-- 0014: chargebook seed — Platinum 2026 fares (Lusaka origin, verified depot board).
-- Large parcels stored as the floor (the ticket printed 'K.. & above').
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Ndola', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Ndola' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Ndola', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Ndola' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Ndola', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Ndola' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kitwe', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kitwe' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kitwe', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kitwe' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kitwe', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kitwe' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Luanshya', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Luanshya' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Luanshya', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Luanshya' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Luanshya', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Luanshya' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalulushi', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalulushi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalulushi', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalulushi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalulushi', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalulushi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mufulira', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mufulira' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mufulira', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mufulira' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mufulira', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mufulira' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chambishi', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chambishi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chambishi', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chambishi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chambishi', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chambishi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chingola', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chingola' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chingola', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chingola' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chingola', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chingola' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chililabombwe', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chililabombwe' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chililabombwe', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chililabombwe' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chililabombwe', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chililabombwe' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasumbalesa', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasumbalesa' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasumbalesa', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasumbalesa' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasumbalesa', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasumbalesa' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpongwe', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpongwe' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpongwe', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpongwe' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpongwe', '15kg+', 120.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpongwe' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kabwe', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kabwe' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kabwe', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kabwe' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kabwe', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kabwe' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kapiri Mposhi', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kapiri Mposhi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kapiri Mposhi', '5-15kg', 60.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kapiri Mposhi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kapiri Mposhi', '15kg+', 80.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kapiri Mposhi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mumbwa', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mumbwa' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mumbwa', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mumbwa' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mumbwa', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mumbwa' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mkushi', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mkushi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mkushi', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mkushi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mkushi', '15kg+', 120.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mkushi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Serenje', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Serenje' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Serenje', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Serenje' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Serenje', '15kg+', 120.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Serenje' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mukando', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mukando' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mukando', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mukando' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mukando', '15kg+', 120.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mukando' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kafue', '0-5kg', 40.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kafue' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kafue', '5-15kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kafue' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kafue', '15kg+', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kafue' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mazabuka', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mazabuka' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mazabuka', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mazabuka' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mazabuka', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mazabuka' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Monze', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Monze' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Monze', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Monze' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Monze', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Monze' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Pemba', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Pemba' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Pemba', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Pemba' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Pemba', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Pemba' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Choma', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Choma' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Choma', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Choma' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Choma', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Choma' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalomo', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalomo' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalomo', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalomo' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalomo', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalomo' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Zimba', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Zimba' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Zimba', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Zimba' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Zimba', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Zimba' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Livingstone', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Livingstone' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Livingstone', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Livingstone' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Livingstone', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Livingstone' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kazungula', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kazungula' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kazungula', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kazungula' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kazungula', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kazungula' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'T.B.Z', '0-5kg', 50.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='T.B.Z' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'T.B.Z', '5-15kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='T.B.Z' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'T.B.Z', '15kg+', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='T.B.Z' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kaoma', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kaoma' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kaoma', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kaoma' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kaoma', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kaoma' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mongu', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mongu' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mongu', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mongu' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mongu', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mongu' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Senanga', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Senanga' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Senanga', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Senanga' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Senanga', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Senanga' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mwandi', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mwandi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mwandi', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mwandi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mwandi', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mwandi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katima Mulilo', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katima Mulilo' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katima Mulilo', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katima Mulilo' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katima Mulilo', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katima Mulilo' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sesheke', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sesheke' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sesheke', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sesheke' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sesheke', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sesheke' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Solwezi', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Solwezi' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Solwezi', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Solwezi' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Solwezi', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Solwezi' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalumbila', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalumbila' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalumbila', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalumbila' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kalumbila', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kalumbila' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kisasa', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kisasa' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kisasa', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kisasa' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kisasa', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kisasa' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Manyama', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Manyama' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Manyama', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Manyama' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Manyama', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Manyama' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chembe', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chembe' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chembe', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chembe' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chembe', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chembe' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mansa', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mansa' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mansa', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mansa' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mansa', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mansa' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Samfya', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Samfya' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Samfya', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Samfya' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Samfya', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Samfya' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nyimba', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nyimba' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nyimba', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nyimba' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nyimba', '15kg+', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nyimba' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katete', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katete' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katete', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katete' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Katete', '15kg+', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Katete' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Petauke', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Petauke' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Petauke', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Petauke' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Petauke', '15kg+', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Petauke' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sinda', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sinda' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sinda', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sinda' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Sinda', '15kg+', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Sinda' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chipata', '0-5kg', 70.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chipata' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chipata', '5-15kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chipata' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chipata', '15kg+', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chipata' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasama', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasama' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasama', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasama' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Kasama', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Kasama' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mbala', '0-5kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mbala' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mbala', '5-15kg', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mbala' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mbala', '15kg+', 180.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mbala' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpika', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpika' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpika', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpika' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Mpika', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Mpika' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Isoka', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Isoka' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Isoka', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Isoka' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Isoka', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Isoka' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chinsali', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chinsali' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chinsali', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chinsali' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Chinsali', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Chinsali' AND weight_class='15kg+' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nakonde', '0-5kg', 100.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nakonde' AND weight_class='0-5kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nakonde', '5-15kg', 130.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nakonde' AND weight_class='5-15kg' AND service='standard');
INSERT INTO quotes (courier_id, from_city, to_city, weight_class, counter_price_zmw, service, updated_at)
SELECT (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1), 'Lusaka', 'Nakonde', '15kg+', 150.00, 'standard', datetime('now')
  WHERE NOT EXISTS (SELECT 1 FROM quotes WHERE courier_id = (SELECT id FROM couriers WHERE name = 'Platinum' LIMIT 1) AND from_city='Lusaka' AND to_city='Nakonde' AND weight_class='15kg+' AND service='standard');
