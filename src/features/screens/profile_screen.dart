import 'package:flutter/material.dart';
import '../widgets/profile_widget.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: ProfileBody(),
    );
  }
}

class ProfileBody extends StatefulWidget {
  const ProfileBody({super.key});

  @override
  State<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<ProfileBody> {
  int selectedTab = 0;

  final List<String> posts = const [
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
  ];

  final List<String> reposts = const [
    "assets/img/2.png",
    "assets/img/1.png",
    "assets/img/2.png",
    "assets/img/1.png",
  ];

  final List<String> saved = const [
    "assets/img/1.png",
    "assets/img/2.png",
  ];

  List<String> get currentList =>
      selectedTab == 0 ? posts : selectedTab == 1 ? reposts : saved;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        children: [
          ProfileCoverAvatar(posts: posts),
          const ProfileNameBio(),
          const ProfileStats(),
          const ProfileButtons(),
          ProfileTabBar(
            selectedTab: selectedTab,
            onTap: (i) => setState(() => selectedTab = i),
          ),
          const Divider(height: 1),
          currentList.isEmpty
              ? const ProfileEmpty()
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(2),
                  itemCount: currentList.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      currentList[i],
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}