-- Replaces the generic seed descriptions from 20260819090000 with copy
-- that actually differentiates the three foods, since the shop screen is
-- about to start rendering this column for the first time.
update special_foods set description = 'Rich, oily fish that sits heavier than the daily kind.'
  where key = 'premium_fish';
update special_foods set description = 'Small bites, big enthusiasm — gone fast, worth it often.'
  where key = 'gourmet_treats';
update special_foods set description = 'The good stuff, saved for special occasions.'
  where key = 'fancy_feast';
