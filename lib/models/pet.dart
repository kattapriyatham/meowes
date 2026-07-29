enum MoodState { sad, content, happy, ecstatic }

MoodState moodStateFromScore(int score) {
  if (score >= 85) return MoodState.ecstatic;
  if (score >= 60) return MoodState.happy;
  if (score >= 25) return MoodState.content;
  return MoodState.sad;
}

class Pet {
  final String userId;
  final int coins;
  final int moodScore;
  final DateTime lastCareAt;
  final DateTime? lastFedAt;
  final DateTime? lastCheckinAt;
  final int feedStreakDays;

  const Pet({
    required this.userId,
    required this.coins,
    required this.moodScore,
    required this.lastCareAt,
    this.lastFedAt,
    this.lastCheckinAt,
    required this.feedStreakDays,
  });

  MoodState get mood => moodStateFromScore(moodScore);

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        userId: json['user_id'] as String,
        coins: json['coins'] as int,
        moodScore: json['mood_score'] as int,
        lastCareAt: DateTime.parse(json['last_care_at'] as String),
        lastFedAt: json['last_fed_at'] == null
            ? null
            : DateTime.parse(json['last_fed_at'] as String),
        lastCheckinAt: json['last_checkin_at'] == null
            ? null
            : DateTime.parse(json['last_checkin_at'] as String),
        feedStreakDays: json['feed_streak_days'] as int,
      );
}

class FeedCooldownException implements Exception {}

class AlreadyCheckedInException implements Exception {}

class InsufficientCoinsException implements Exception {}
