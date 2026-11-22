import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/capture_screen.dart';
import 'screens/containers_screen.dart';
import 'screens/houses_screen.dart';
import 'screens/inventory_list_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/search_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HomeScatoloApp());
}

class HomeScatoloApp extends StatelessWidget {
  const HomeScatoloApp({super.key});

  static final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const HousesScreen(),
      ),
      GoRoute(
        path: '/rooms',
        builder: (BuildContext context, GoRouterState state) {
          final int? houseId =
              int.tryParse(state.uri.queryParameters['houseId'] ?? '');
          return RoomsScreen(houseId: houseId);
        },
      ),
      GoRoute(
        path: '/containers',
        builder: (BuildContext context, GoRouterState state) {
          final int? roomId =
              int.tryParse(state.uri.queryParameters['roomId'] ?? '');
          return ContainersScreen(roomId: roomId);
        },
      ),
      GoRoute(
        path: '/capture',
        builder: (BuildContext context, GoRouterState state) {
          final int? containerId =
              int.tryParse(state.uri.queryParameters['containerId'] ?? '');
          return CaptureScreen(containerId: containerId);
        },
      ),
      GoRoute(
        path: '/inventory',
        builder: (BuildContext context, GoRouterState state) {
          final int? containerId =
              int.tryParse(state.uri.queryParameters['containerId'] ?? '');
          return InventoryListScreen(
            containerId: containerId,
            title: state.uri.queryParameters['title'],
          );
        },
      ),
      GoRoute(
        path: '/items/:id',
        builder: (BuildContext context, GoRouterState state) =>
            ItemDetailScreen(itemId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/search',
        builder: (BuildContext context, GoRouterState state) =>
            const SearchScreen(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeController,
      builder: (BuildContext context, ThemeMode mode, _) {
        return MaterialApp.router(
          title: 'Home Scatolo',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}
