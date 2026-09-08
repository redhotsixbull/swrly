class Post {
  Post({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
      );
}
