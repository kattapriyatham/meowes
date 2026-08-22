enum MoodState { sad, content, happy, ecstatic }

MoodState moodStateFromScore(int score) {
  if (score >= 85) return MoodState.ecstatic;
  if (score >= 60) return MoodState.happy;
  if (score >= 25) return MoodState.content;
  return MoodState.sad;
}

class Pet {
  final String userId;
  final String name;
  final int coins;
  final int moodScore;
  final DateTime lastCareAt;
  final DateTime? lastFedAt;
  final String? lastFedFoodKey;
  final DateTime? lastCheckinAt;
  final int feedStreakDays;

  /// Independent per-food cooldown clocks — feeding fish doesn't touch
  /// treats' or dry food's own last-fed time. See
  /// supabase/migrations/20260815160000_independent_food_cooldowns.sql.
  final DateTime? lastFishFedAt;
  final DateTime? lastTreatsFedAt;
  final DateTime? lastDryFoodFedAt;

  /// Cooldown clock for purchased special foods — separate from the three
  /// regular-food clocks above since a special food's cooldown is keyed to
  /// which specific special food was last fed, not a fixed food type. See
  /// supabase/migrations/20260819090000_special_food_inventory.sql.
  final String? lastSpecialFoodId;
  final DateTime? lastSpecialFedAt;

  const Pet({
    required this.userId,
    required this.name,
    required this.coins,
    required this.moodScore,
    required this.lastCareAt,
    this.lastFedAt,
    this.lastFedFoodKey,
    this.lastCheckinAt,
    required this.feedStreakDays,
    this.lastFishFedAt,
    this.lastTreatsFedAt,
    this.lastDryFoodFedAt,
    this.lastSpecialFoodId,
    this.lastSpecialFedAt,
  });

  MoodState get mood => moodStateFromScore(moodScore);

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        userId: json['user_id'] as String,
        name: json['name'] as String,
        coins: json['coins'] as int,
        moodScore: json['mood_score'] as int,
        lastCareAt: DateTime.parse(json['last_care_at'] as String),
        lastFedAt: json['last_fed_at'] == null
            ? null
            : DateTime.parse(json['last_fed_at'] as String),
        lastFedFoodKey: json['last_fed_food_key'] as String?,
        lastCheckinAt: json['last_checkin_at'] == null
            ? null
            : DateTime.parse(json['last_checkin_at'] as String),
        feedStreakDays: json['feed_streak_days'] as int,
        lastFishFedAt: json['last_fish_fed_at'] == null
            ? null
            : DateTime.parse(json['last_fish_fed_at'] as String),
        lastTreatsFedAt: json['last_treats_fed_at'] == null
            ? null
            : DateTime.parse(json['last_treats_fed_at'] as String),
        lastDryFoodFedAt: json['last_dry_food_fed_at'] == null
            ? null
            : DateTime.parse(json['last_dry_food_fed_at'] as String),
        lastSpecialFoodId: json['last_special_food_id'] as String?,
        lastSpecialFedAt: json['last_special_fed_at'] == null
            ? null
            : DateTime.parse(json['last_special_fed_at'] as String),
      );
}

class FeedCooldownException implements Exception {}

class AlreadyCheckedInException implements Exception {}

class InsufficientCoinsException implements Exception {}
