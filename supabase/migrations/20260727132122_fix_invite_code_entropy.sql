-- The initial migration's invite_code default used md5(random()::text) as a
-- workaround for gen_random_bytes() not resolving unqualified — Supabase
-- installs pgcrypto into the `extensions` schema, not the default search
-- path. Group invite codes are effectively bearer secrets (anyone holding
-- one can join the group), so they need cryptographically secure
-- randomness, not pg's plain (non-crypto) random(). Schema-qualify instead.
alter table groups
  alter column invite_code set default encode(extensions.gen_random_bytes(6), 'hex');
