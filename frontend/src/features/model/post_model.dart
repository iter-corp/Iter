class Post {
  final String image;
  final String username;
  final String handle;
  final String caption;
  final String avatar;
  final bool isPrivate;

  Post({
    required this.image,
    required this.username,
    required this.handle,
    required this.caption,
    required this.avatar,
    this.isPrivate = false,
  });
}