import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/realtime_service.dart';
import 'services/ai_insight_service.dart';
import 'services/ble_service.dart';
import 'services/database_service.dart';
import 'services/baseline_service.dart';
import 'services/notification_service.dart';
import 'services/change_detector.dart';
import 'services/sync_service.dart';
import 'services/theme_provider.dart';
import 'theme/physiopano_tokens.dart';
import 'motion/motion.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/app_shell.dart';
import 'screens/check_in_screen.dart';
import 'screens/motion_lab_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      runApp(_ErrorApp('Firebase init failed: ${e.code} ${e.message}'));
      return;
    }
    // duplicate-app is fine — already initialized by google-services plugin
  } catch (e) {
    runApp(_ErrorApp('Firebase init failed: $e'));
    return;
  }

  // Analytics & Crashlytics initialization
  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    
    // Log app open manually
    FirebaseAnalytics.instance.logAppOpen();
  }

  // Initialize core services
  final db = DatabaseService();
  final notificationService = NotificationService();
  try {
    await notificationService.init();
  } catch (_) {}

  final authService = AuthService();
  final bleService = BleService();
  try {
    await bleService.init();
  } catch (_) {}

  final baselineService = BaselineService(db);
  // Personal-baseline change detection (replaces the WESAD classifier,
  // the chronic-stress alerts and the emergency-email automation).
  final changeDetector = ChangeDetector(notificationService, db);
  final syncService = SyncService(db, authService);

  // Inject AI services into BLE pipeline
  final realtimeService = RealtimeService();
  final aiInsightService = AiInsightService();

  bleService.setServices(
    changeDetector: changeDetector,
    baselineService: baselineService,
    notificationService: notificationService,
    dbService: db,
    realtimeService: realtimeService,
    syncService: syncService,
  );

  // Per-user loading (baseline, sessions, sync) happens once, in _AuthGate /
  // _OnboardingGate, for whoever is signed in — not here as well.

  runApp(StressMonitorApp(
    authService: authService,
    bleService: bleService,
    db: db,
    baselineService: baselineService,
    changeDetector: changeDetector,
    notificationService: notificationService,
    syncService: syncService,
    aiInsightService: aiInsightService,
  ));
}

class StressMonitorApp extends StatefulWidget {
  final AuthService authService;
  final BleService bleService;
  final DatabaseService db;
  final BaselineService baselineService;
  final ChangeDetector changeDetector;
  final NotificationService notificationService;
  final SyncService syncService;
  final AiInsightService aiInsightService;

  const StressMonitorApp({
    super.key,
    required this.authService,
    required this.bleService,
    required this.db,
    required this.baselineService,
    required this.changeDetector,
    required this.notificationService,
    required this.syncService,
    required this.aiInsightService,
  });

  @override
  State<StressMonitorApp> createState() => _StressMonitorAppState();
}

class _StressMonitorAppState extends State<StressMonitorApp> {
  late final StreamSubscription<String?> _notifSub;

  @override
  void initState() {
    super.initState();
    _notifSub = widget.notificationService.selectNotificationStream
        .listen((String? payload) {
      // A noticed change offers a validated 2-minute check-in; the result
      // then suggests the least intensive safe next stop.
      if (payload == 'change_noticed') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const CheckInScreen(promptedByChange: true)),
        );
      }
    });
  }

  @override
  void dispose() {
    _notifSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authService),
        ChangeNotifierProvider.value(value: widget.bleService),
        Provider.value(value: widget.db),
        ChangeNotifierProvider.value(value: widget.baselineService),
        ChangeNotifierProvider.value(value: widget.changeDetector),
        Provider.value(value: widget.notificationService),
        ChangeNotifierProvider.value(value: widget.syncService),
        Provider.value(value: widget.aiInsightService),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'PHYSIOPAÑO',
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final data = MediaQuery.of(context);
              return MediaQuery(
                data: data.copyWith(
                  textScaler: data.textScaler.clamp(
                    minScaleFactor: 1.0,
                    maxScaleFactor: 2.0,
                  ),
                ),
                child: child!,
              );
            },
            themeMode: themeProvider.mode,
            // PHYSIOPAÑO Wayfinding (design-system/tokens.json)
            theme: PpTheme.light(),
            darkTheme: PpTheme.dark(),
            // Design review without signing in (both off by default):
            //   --dart-define=MOTION_LAB=true      motion/art catalogue
            //   --dart-define=DESIGN_PREVIEW=true  the app shell with no account (no data)
            home: const bool.fromEnvironment('MOTION_LAB')
                ? const MotionLabScreen()
                : const bool.fromEnvironment('DESIGN_PREVIEW')
                    ? const AppShell()
                    : const _AuthGate(),
          );
        },
      ),
    );
  }
}

/// The single session state machine. This is the app's root route and is
/// never replaced: every screen change between "signed out", "setting up"
/// and "using the app" happens here, driven by auth state.
///
///   auth unknown  -> splash
///   signed out    -> LoginScreen   (and the previous person's state is cleared)
///   signed in     -> _OnboardingGate(uid) -> OnboardingScreen | AppShell
///
/// Screens never push LoginScreen/AppShell themselves; to sign out they call
/// AuthService.signOut() and pop back to this route.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _lastUid;

  /// Clear everything that belongs to the person who just left, so the next
  /// account on this phone never sees their sessions, baseline or sync.
  void _clearSession() {
    context.read<SyncService>().stopListening();
    context.read<BaselineService>().reset();
    unawaited(context.read<BleService>().clearUser());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoader();
        }
        final uid = snapshot.data?.uid;
        if (_lastUid != null && _lastUid != uid) {
          // Signed out, or switched account: drop the previous person's state.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _clearSession();
          });
        }
        _lastUid = uid;
        if (uid == null) return const LoginScreen();
        // Keyed by uid so a different account always starts a fresh gate.
        return _OnboardingGate(key: ValueKey(uid), userId: uid);
      },
    );
  }
}

/// Loads the signed-in person's data, then shows onboarding (until it is
/// complete) or the app. Completion is reported back here, never by
/// navigating away from the root.
class _OnboardingGate extends StatefulWidget {
  final String userId;
  const _OnboardingGate({super.key, required this.userId});

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late Future<bool> _readyFuture;
  bool _justCompleted = false;

  @override
  void initState() {
    super.initState();
    _readyFuture = _init();
  }

  Future<bool> _init() async {
    final db = context.read<DatabaseService>();
    final sync = context.read<SyncService>();
    final baseline = context.read<BaselineService>();
    final ble = context.read<BleService>();
    final auth = context.read<AuthService>();

    // Sign-up answers (name, emergency contact…) are written locally first,
    // before anything else reads the profile.
    final pending = auth.takePendingProfile();
    if (pending != null) {
      await db.saveSettings(widget.userId, pending);
    }

    // Check local SQLite first — always works offline
    final local = await db.getSettings(widget.userId);
    final localComplete = (local?['onboarding_complete'] as int? ?? 0) == 1;

    // Cloud sync — wrapped in try/catch so offline doesn't block the flow
    try {
      if (local == null || !localComplete) {
        await sync.pullProfileFromCloud().timeout(const Duration(seconds: 6));
      }
      await sync.fetchSessionsFromCloud().timeout(const Duration(seconds: 6));
    } catch (_) {
      // Network unavailable — continue with local data
    }

    try {
      sync.startListening();
    } catch (_) {}

    await baseline.loadBaseline(widget.userId);

    ble.setUserId(widget.userId);
    await ble.loadSessionsForUser(widget.userId);

    final settings = await db.getSettings(widget.userId);
    return (settings?['onboarding_complete'] as int? ?? 0) == 1;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _readyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoader();
        }
        if (snapshot.data != true && !_justCompleted) {
          return OnboardingScreen(onComplete: () => setState(() => _justCompleted = true));
        }
        return const AppShell();
      },
    );
  }
}

class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AuroraBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Reveal(child: PanoMascot(mood: PanoMood.wave, size: 120)),
              const SizedBox(height: 22),
              Reveal(
                index: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandTile(size: 40),
                    const SizedBox(width: 12),
                    Text('PHYSIOPAÑO', style: text.headlineSmall),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Reveal(index: 2, child: Text('Getting your space ready.', style: text.bodyLarge)),
              const SizedBox(height: 26),
              const Reveal(index: 3, child: SizedBox(width: 120, child: LinearProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
