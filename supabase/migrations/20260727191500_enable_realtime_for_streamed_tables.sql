-- Every `.stream()` call in the repositories (FriendRepository.watchFriendships,
-- GroupRepository.watchMyGroups, SettlementRepository's pending-settlement
-- stream) subscribes to Realtime postgres_changes on top of its initial
-- REST fetch. None of `friendships`, `group_members`, or `settlements` had
-- ever been added to the `supabase_realtime` publication, so every one of
-- those streams got a channelError right after its correct initial fetch
-- ("Please check Realtime is enabled for the given connect parameters") —
-- confirmed by instrumenting HomeScreen's StreamBuilder directly: the
-- initial snapshot briefly held the real rows, then flipped to an error
-- snapshot (data becomes null on an AsyncSnapshot error) a moment later,
-- which is why HomeScreen's Friends/Groups sections always render empty
-- despite real data existing.
alter publication supabase_realtime add table friendships;
alter publication supabase_realtime add table group_members;
alter publication supabase_realtime add table settlements;
