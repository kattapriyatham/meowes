class Activity {
  final String id;
  final String key;
  final String name;
  final String category;
  final int coinCost;
  final String imageAsset;
  final String caption;

  const Activity({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.coinCost,
    required this.imageAsset,
    required this.caption,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        coinCost: json['coin_cost'] as int,
        imageAsset: json['image_asset'] as String,
        caption: json['caption'] as String,
      );
}
