-- Lets users name their pet, edited from the profile section.
alter table pets add column name text not null default 'Whiskers';
