import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coil/src/features/model/main_screen.dart';
import 'package:coil/src/features/widgets/desktop_nav_sidebar.dart';
import 'package:coil/src/features/widgets/desktop_right_sidebar.dart';
import 'package:coil/src/providers/auth_providers.dart';
import 'package:coil/src/providers/admin_providers.dart';
import 'package:coil/src/providers/chat_providers.dart';
import 'package:coil/src/providers/post_providers.dart';
import 'package:coil/src/providers/theme_provider.dart';
import 'package:coil/src/services/admin_service.dart';
import 'package:coil/src/services/chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildTestApp({required Size screenSize}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inboxProvider.overrideWith((ref) => Stream.value(<ChatConversation>[])),
        adminEventsProvider.overrideWith((ref) => Stream.value(<AdminEvent>[])),
        currentUserDocProvider.overrideWith((ref) => Stream.value(<String, dynamic>{
          'username': 'TestUser',
          'handle': '@tester',
        })),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        adminConfigProvider.overrideWith((ref) => Stream.value(const AdminConfig())),
        homeFeedProvider.overrideWith((ref) => const AsyncValue.data([])),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: const MainScreen(),
        ),
      ),
    );
  }

  testWidgets('Desktop (1920x1080) renders 3-column layout with full sidebar and right sidebar', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildTestApp(screenSize: const Size(1920, 1080)));
    await tester.pump();

    // Left sidebar is present and NOT compact
    expect(find.byType(DesktopNavSidebar), findsOneWidget);
    final sidebar = tester.widget<DesktopNavSidebar>(find.byType(DesktopNavSidebar));
    expect(sidebar.isCompact, isFalse);

    // Right sidebar is present on wide desktop
    expect(find.byType(DesktopRightSidebar), findsOneWidget);
  });

  testWidgets('Tablet (820x1180) renders 2-column layout with compact nav rail and no right sidebar', (tester) async {
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildTestApp(screenSize: const Size(820, 1180)));
    await tester.pump();

    // Left sidebar is present in compact mode
    expect(find.byType(DesktopNavSidebar), findsOneWidget);
    final sidebar = tester.widget<DesktopNavSidebar>(find.byType(DesktopNavSidebar));
    expect(sidebar.isCompact, isTrue);

    // Right sidebar is omitted to give maximum space to the feed
    expect(find.byType(DesktopRightSidebar), findsNothing);
  });

  testWidgets('Mobile (400x844) renders 1-column layout without sidebars', (tester) async {
    tester.view.physicalSize = const Size(400, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildTestApp(screenSize: const Size(400, 844)));
    await tester.pump();

    // Sidebars should not be rendered on mobile
    expect(find.byType(DesktopNavSidebar), findsNothing);
    expect(find.byType(DesktopRightSidebar), findsNothing);
  });
}
