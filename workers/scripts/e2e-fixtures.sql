UPDATE riders SET active = 1 WHERE full_name <> 'Queue Test Rider';
UPDATE riders SET active = 0 WHERE full_name = 'Queue Test Rider';
