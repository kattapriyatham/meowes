-- Points bowl_asset at the actual filenames added under
-- assets/images/pet/ (bowl_special_fish.png, bowl_gourmet.png,
-- bowl_feast.png) — the 20260819090000 seed used placeholder names
-- (bowl_premium_fish.png etc.) that never had matching files, so these
-- fell back to the generic set_meal_outlined icon in the shop UI.
update special_foods set bowl_asset = 'assets/images/pet/bowl_special_fish.png'
  where key = 'premium_fish';
update special_foods set bowl_asset = 'assets/images/pet/bowl_gourmet.png'
  where key = 'gourmet_treats';
update special_foods set bowl_asset = 'assets/images/pet/bowl_feast.png'
  where key = 'fancy_feast';
