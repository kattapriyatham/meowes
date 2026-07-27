class AppUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? phoneNumber;

  AppUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.phoneNumber,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatar_url'] as String?,
        phoneNumber: json['phone_number'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'phone_number': phoneNumber,
      };
}
