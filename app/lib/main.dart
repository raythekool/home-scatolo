import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/capture_screen.dart';
import 'screens/containers_screen.dart';
import 'screens/houses_screen.dart';
import 'screens/inventory_list_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/search_screen.dart';

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
    const Color ink = Color(0xFF123447);
    const Color scanOrange = Color(0xFFE66B4A);
    const Color paper = Color(0xFFF4F2EC);
    return MaterialApp.router(
      title: 'Home Scatolo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: ink,
          secondary: scanOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: paper,
          foregroundColor: ink,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE2E6E2)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: scanOrange,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}
