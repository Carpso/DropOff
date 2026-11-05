-- Sample riders/drivers for the demo team. Same numbers as the Flutter
-- first-run team in app/lib/state/app_store.dart (sampleTeam) so an assigned
-- job lines up with the rider shown on the team screen.
INSERT OR IGNORE INTO riders (phone, full_name, vehicle, active) VALUES
  ('260977123456', 'Bwalya Mwale',  'Motorcycle - CFMoto',    1),
  ('260966234567', 'Chanda Nkole',  'Toyota Vitz - HB 4281',  1),
  ('260955345678', 'Mutinta Zulu',  'Cargo tricycle',         1);
