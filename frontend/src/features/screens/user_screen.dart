import 'package:flutter/material.dart';
import '../widgets/user_profile_widget.dart';

class UserProfileScreen extends StatefulWidget {
  final String username;
  final String handle;
  final String avatar;
  final bool isPrivate;

  const UserProfileScreen({
    super.key,
    required this.username,
    required this.handle,
    required this.avatar,
    this.isPrivate = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  int selectedTab = 0;
  bool isFollowing = false;

  final List<String> posts = [
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
  ];

  final List<String> reposts = [
    "assets/img/2.png",
    "assets/img/1.png",
  ];

  List<String> get currentList =>
      selectedTab == 0 ? posts : reposts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            /// COVER + AVATAR + BACK
            UserCoverAvatar(
              avatar: widget.avatar,
              posts: posts,
              isPrivate: widget.isPrivate,
              onBack: () => Navigator.pop(context),
            ),

            /// NAME + BIO
            UserNameBio(
              username: widget.username,
              handle: widget.handle,
            ),

            /// STATS
            const UserStats(),

            /// BUTTONS
            UserButtons(
              isFollowing: isFollowing,
              isPrivate: widget.isPrivate,
              onFollowTap: () =>
                  setState(() => isFollowing = !isFollowing),
            ),

            /// PRIVATE or PUBLIC content
            widget.isPrivate && !isFollowing
                ? const UserPrivateMessage()
                : Column(
                    children: [
                      UserTabBar(
                        selectedTab: selectedTab,
                        onTap: (i) =>
                            setState(() => selectedTab = i),
                      ),
                      const Divider(height: 1),
                      currentList.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: 60),
                              child: Center(
                                child: Text("No posts yet",
                                    style: TextStyle(
                                        color: Colors.grey)),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(2),
                              itemCount: currentList.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              itemBuilder: (context, i) => ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4),
                                child: Image.asset(
                                  currentList[i],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}