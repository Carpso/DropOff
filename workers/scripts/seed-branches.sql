-- Sample Lusaka branches keyed to the LIVE chargebook ids. Admin-editable.
-- Every active courier gets at least one walk-in point so a seller always
-- picks a specific depot branch (first-mile destination), never a vague city.
INSERT OR IGNORE INTO courier_branches (courier_id, name, city, address, lat, lng) VALUES
  -- id 1 (featured / primary Lusaka partner)
  (1, 'Chibolya depot', 'Lusaka', 'Chibolya Rd, industrial area', -15.4255, 28.2805),
  (1, 'Longacres branch', 'Lusaka', 'Longacres, Airport Rd strip', -15.3869, 28.3227),
  (1, 'Kabulonga branch', 'Lusaka', 'Kabulonga, near Kabulonga Rd shops', -15.4123, 28.3239),
  (1, 'Woodlands branch', 'Lusaka', 'Woodlands Shopping area', -15.4280, 28.3311),
  (1, 'Chilenje branch', 'Lusaka', 'Chilenje South', -15.4353, 28.3372),
  (1, 'Cairo Road desk', 'Lusaka', 'Cairo Road, city centre', -15.4167, 28.2767),
  -- id 3
  (3, 'Longacres office', 'Lusaka', 'Longacres commercial park', -15.3869, 28.3227),
  (3, 'Cairo Road desk', 'Lusaka', 'Cairo Road, city centre', -15.4167, 28.2767),
  (3, 'Kabwata counter', 'Lusaka', 'Kabwata market area', -15.4360, 28.3040),
  -- id 4
  (4, 'Longacres office', 'Lusaka', 'Longacres commercial park', -15.3869, 28.3227),
  (4, 'Great East Rd desk', 'Lusaka', 'Great East Rd near Arcades', -15.3900, 28.3260),
  -- id 6
  (6, 'Northmead depot', 'Lusaka', 'Northmead, Los Angeles Blvd', -15.3864, 28.3297),
  (6, 'Rhodes Park desk', 'Lusaka', 'Rhodes Park, Independence Ave', -15.4120, 28.2980),
  -- id 14 (DHL)
  (14, 'Cairo Road service point', 'Lusaka', 'Cairo Road, city centre', -15.4167, 28.2767),
  (14, 'Arcades service point', 'Lusaka', 'Arcades Shopping Centre, Great East Rd', -15.3900, 28.3260),
  (14, 'Kabulonga service point', 'Lusaka', 'Kabulonga Rd shops', -15.4123, 28.3239),
  -- id 22
  (22, 'Lusaka office', 'Lusaka', 'Lusaka city centre', -15.4167, 28.2833),
  (22, 'Airport Rd desk', 'Lusaka', 'Airport Rd, Longacres', -15.3869, 28.3227),
  -- Remaining Lusaka couriers from the chargebook (one+ walk-in each)
  (2, 'Zampost Provident House', 'Lusaka', 'Cairo Rd, Provident House', -15.4266, 28.2792),
  (2, 'Zampost Kafue Rd counter', 'Lusaka', 'Kafue Rd near industrial', -15.4400, 28.2900),
  (5, 'PDN service centre', 'Lusaka', 'PostDotNet Lusaka outlet', -15.4167, 28.2767),
  (5, 'PDN Arcades outlet', 'Lusaka', 'Arcades Shopping Centre', -15.3900, 28.3260),
  (7, 'Gavic Express desk', 'Lusaka', 'Indeco House, Cairo Road', -15.4167, 28.2767),
  (8, 'Peshi Kwacha Square', 'Lusaka', 'Kwacha Square Mall', -15.4200, 28.2850),
  (9, 'Eastlight DGM Complex', 'Lusaka', 'Mukwa Rd, DGM Complex', -15.4050, 28.3100),
  (10, 'Shipflex Greenlane', 'Lusaka', 'Greenlane, Kabulonga', -15.4123, 28.3239),
  (11, 'MacSpeedy Rhodes Park', 'Lusaka', 'Provident St, Rhodes Park', -15.4120, 28.2980),
  (12, 'Amezam Kafue Rd', 'Lusaka', 'Kafue Rd Depot', -15.4400, 28.2900),
  (13, 'Mazhandu InterCity counter', 'Lusaka', 'InterCity Bus Station', -15.4167, 28.2833),
  (15, 'Shalom terminus counter', 'Lusaka', 'Shalom Terminus', -15.4167, 28.2833),
  (16, 'Zampost Kitwe main', 'Kitwe', 'Kitwe Main Post Office', -12.8014, 28.2132),
  (17, 'PDN Livingstone outlet', 'Livingstone', 'PDN Livingstone Outlet', -17.8419, 25.8596),
  (18, 'PDN Mukuba Mall', 'Ndola', 'Mukuba Mall Outlet', -12.9680, 28.6320);
