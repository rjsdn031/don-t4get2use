import 'package:dont4get2use2/pages/debug_scenario_runner_page.dart';
import 'package:dont4get2use2/pages/gifticon_list_page.dart';
import 'package:dont4get2use2/services/debug_now_provider.dart';
import 'package:dont4get2use2/services/debug_time_controller.dart';
import 'package:dont4get2use2/services/gifticon_services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/gifticon_worker_dispatcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Hive.initFlutter();

  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Don\'t Forget to Use!',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const AppBootstrapPage(),
    );
  }
}

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key});

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  late final DebugTimeController _debugTimeController;
  late final Future<GifticonServices> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _debugTimeController = DebugTimeController();
    _servicesFuture = GifticonServices.create(
      nowProvider: DebugNowProvider(_debugTimeController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GifticonServices>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '앱 초기화 중 오류가 발생했습니다.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final services = snapshot.data!;
        const bool useDebugRunner = true;

        if (useDebugRunner) {
          return DebugScenarioRunnerPage(
            services: services,
            debugTimeController: _debugTimeController,
          );
        }

        return GifticonListPage(
          servicesOverride: services,
          nowProviderOverride: DebugNowProvider(_debugTimeController),
        );
      },
    );
  }
}