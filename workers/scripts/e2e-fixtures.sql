UPDATE auth_users SET role = 'partner', courier_id = 1 WHERE email = 'partner.test@carpsosolutions.store';
UPDATE jobs SET pickup_lat = -15.4167, pickup_lng = 28.2833 WHERE ref = 'DRO-261105-G34WU';
UPDATE riders SET last_lat = -15.4167, last_lng = 28.2833, active = 1 WHERE id = 4;
