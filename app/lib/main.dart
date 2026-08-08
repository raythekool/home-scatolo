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
        builder: (BuildContext context, GoRouterState state) =>
            const RoomsScreen(),
      ),
      GoRoute(
        path: '/containers',
        builder: (BuildContext context, GoRouterState state) =>
            const ContainersScreen(),
      ),
      GoRoute(
        path: '/capture',
        builder: (BuildContext context, GoRouterState state) =>
            const CaptureScreen(),
      ),
      GoRoute(
        path: '/inventory',
        builder: (BuildContext context, GoRouterState state) =>
            const InventoryListScreen(),
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
    return MaterialApp.router(
      title: 'Home Scatolo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
