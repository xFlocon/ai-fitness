import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/store.dart';
import '../features/onboarding/onboarding.dart';
import '../features/dashboard/dashboard.dart';
import '../features/nutrition/nutrition.dart';
import '../features/workouts/workouts.dart';
import '../features/ai_assistant/chat.dart';
import '../features/profile/profile.dart';
import '../features/settings/settings.dart';
import '../features/body_progress/progress.dart';

final appearanceProvider = FutureProvider((ref) {
  ref.watch(changesProvider);
  return ref.watch(storeProvider).get('appearance');
});
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final profile = await ref.read(storeProvider).get('profile');
      if (profile == null && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/nutrition', builder: (_, _) => const NutritionPage()),
          GoRoute(path: '/workouts', builder: (_, _) => const WorkoutsPage()),
          GoRoute(path: '/chat', builder: (_, _) => const ChatPage()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        ],
      ),
      GoRoute(
        path: '/meal',
        builder: (_, state) => MealEditor(
          id: state.uri.queryParameters['id'],
          favorite: state.uri.queryParameters['favorite'],
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/providers', builder: (_, _) => const ProvidersPage()),
      GoRoute(
        path: '/provider',
        builder: (_, state) =>
            ProviderEditor(id: state.uri.queryParameters['id']),
      ),
      GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
      GoRoute(
        path: '/workout',
        builder: (_, state) =>
            WorkoutEditor(id: state.uri.queryParameters['id']),
      ),
      GoRoute(
        path: '/session',
        builder: (_, state) =>
            WorkoutSession(id: state.uri.queryParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class FitnessApp extends ConsumerWidget {
  const FitnessApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).value;
    final seed = Color((appearance?['color'] as int?) ?? 0xffa3ff6f);
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final colors =
          ColorScheme.fromSeed(
            seedColor: dark ? seed : const Color(0xff388d44),
            brightness: brightness,
          ).copyWith(
            primary: dark ? seed : const Color(0xff277a39),
            secondary: const Color(0xff65b8ff),
            surface: dark ? const Color(0xff151b23) : Colors.white,
          );
      return ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: dark
            ? const Color(0xff0b0f14)
            : const Color(0xfff7f9fc),
        visualDensity: VisualDensity.standard,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .22),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colors.surface,
          indicatorColor: colors.primary.withValues(alpha: .16),
        ),
      );
    }

    return MaterialApp.router(
      title: 'AI Fitness',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (appearance?['mode']) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final reduced =
            media.disableAnimations || appearance?['reduceMotion'] == true;
        return MediaQuery(
          data: media.copyWith(disableAnimations: reduced),
          child: child!,
        );
      },
    );
  }
}

class HomeShell extends StatelessWidget {
  final String location;
  final Widget child;
  const HomeShell({super.key, required this.location, required this.child});
  static const paths = ['/', '/nutrition', '/workouts', '/chat', '/profile'];
  @override
  Widget build(BuildContext context) {
    final index = paths.indexOf(location).clamp(0, 4);
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          context.go(paths[i]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Alimentação',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Treinos',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistente',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
      floatingActionButton: location == '/chat'
          ? null
          : FloatingActionButton(
              tooltip: 'Registrar refeição',
              onPressed: () => context.push('/meal'),
              child: const Icon(Icons.add_a_photo_outlined),
            ),
    );
  }
}
