class PetMemory {
  final String id;
  final String activityId;
  final String activityName;
  final String caption;
  final String imageAsset;
  final int coinsSpent;
  final DateTime completedAt;

  const PetMemory({
    required this.id,
    required this.activityId,
    required this.activityName,
    required this.caption,
    required this.imageAsset,
    required this.coinsSpent,
    required this.completedAt,
  });

  factory PetMemory.fromJson(Map<String, dynamic> json) => PetMemory(
        id: json['id'] as String,
        activityId: json['activity_id'] as String,
        activityName: json['activity_name'] as String,
        caption: json['caption'] as String,
        imageAsset: json['image_asset'] as String,
        coinsSpent: json['coins_spent'] as int,
        completedAt: DateTime.parse(json['completed_at'] as String),
      );
}
