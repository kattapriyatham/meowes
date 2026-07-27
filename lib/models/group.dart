class Group {
  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        createdBy: json['created_by'] as String,
        inviteCode: json['invite_code'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_by': createdBy,
        'invite_code': inviteCode,
      };
}
