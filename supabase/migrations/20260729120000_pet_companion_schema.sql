-- Pets: one row per user, holds coin balance and mood state.
create table pets (
  user_id uuid primary key references users(id) on delete cascade,
  coins integer not null default 25 check (coins >= 0),
  mood_score integer not null default 60 check (mood_score between 0 and 100),
  last_care_at timestamptz not null default now(),
  last_fed_at timestamptz,
  last_checkin_at date,
  feed_streak_days integer not null default 0,
  last_feed_streak_date date,
  created_at timestamptz not null default now()
);

alter table pets enable row level security;

create policy pets_select_owner on pets
  for select to authenticated using (auth.uid() = user_id);

create policy pets_insert_owner on pets
  for insert to authenticated with check (auth.uid() = user_id);

create policy pets_update_owner on pets
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Activities: shared read-only catalog, managed by migrations only.
create table activities (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  category text not null,
  coin_cost integer not null check (coin_cost > 0),
  image_asset text not null,
  caption text not null
);

alter table activities enable row level security;

create policy activities_select_all on activities
  for select to authenticated using (true);

insert into activities (key, name, category, coin_cost, image_asset, caption) values
  ('morning_walk', 'Morning Walk', 'Walks', 20, 'assets/images/activities/morning_walk.webp', 'We watched the sun come up together. You walk too fast, by the way.'),
  ('watching_the_rain', 'Watching the Rain', 'Relaxation', 30, 'assets/images/activities/watching_the_rain.webp', 'We just sat by the window and watched the rain fall. Perfect nap weather.'),
  ('spa_day', 'Spa Day', 'Grooming', 80, 'assets/images/activities/spa_day.webp', 'You brushed me for an hour. I pretended not to enjoy it. I enjoyed it.'),
  ('park_picnic', 'Park Picnic', 'Outdoor Adventures', 60, 'assets/images/activities/park_picnic.webp', 'We spent the afternoon under a big tree. I almost stole your sandwich.'),
  ('beach_trip', 'Beach Trip', 'Outdoor Adventures', 150, 'assets/images/activities/beach_trip.webp', 'I do not like sand. I like you. Mixed feelings about today.'),
  ('camping', 'Camping', 'Outdoor Adventures', 220, 'assets/images/activities/camping.webp', 'We slept under the stars. I kept watch all night, obviously.'),
  ('chased_a_butterfly', 'Chased a Butterfly', 'Funny Moments', 25, 'assets/images/activities/chased_a_butterfly.webp', 'I almost had it. Almost. Did you see that jump though?'),
  ('birthday_celebration', 'Birthday Celebration', 'Special Occasions', 500, 'assets/images/activities/birthday_celebration.webp', 'You made today feel special. Thank you for always showing up for me.');

-- Pet memories: permanent journal of completed activities.
create table pet_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  activity_id uuid not null references activities(id),
  activity_name text not null,
  caption text not null,
  image_asset text not null,
  coins_spent integer not null,
  completed_at timestamptz not null default now()
);

create index idx_pet_memories_user on pet_memories(user_id, completed_at desc);

alter table pet_memories enable row level security;

create policy pet_memories_select_owner on pet_memories
  for select to authenticated using (auth.uid() = user_id);

create policy pet_memories_insert_owner on pet_memories
  for insert to authenticated with check (auth.uid() = user_id);
