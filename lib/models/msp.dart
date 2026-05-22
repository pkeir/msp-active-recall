class Msp {
  final String name;
  final String party;
  final String slug;
  final String imagePath;
  final String profileUrl;

  const Msp({
    required this.name,
    required this.party,
    required this.slug,
    required this.imagePath,
    required this.profileUrl,
  });

  factory Msp.fromJson(Map<String, dynamic> json) => Msp(
        name: json['name'] as String,
        party: json['party'] as String,
        slug: json['slug'] as String,
        imagePath: json['image'] as String,
        profileUrl: json['profile_url'] as String,
      );
}
