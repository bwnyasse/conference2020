import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:conferenceapp/agenda/bloc/bloc.dart';
import 'package:conferenceapp/agenda/helpers/agenda_layout_helper.dart';
import 'package:conferenceapp/agenda/repository/contentful_client.dart';
import 'package:conferenceapp/agenda/repository/contentful_talks_repository.dart';
import 'package:conferenceapp/agenda/repository/file_storage.dart';
import 'package:conferenceapp/agenda/repository/reactive_talks_repository.dart';
import 'package:conferenceapp/agenda/repository/talks_repository.dart';
import 'package:conferenceapp/analytics.dart';
import 'package:conferenceapp/main_page/home_page.dart';
import 'package:conferenceapp/notifications/repository/notifications_repository.dart';
import 'package:conferenceapp/notifications/repository/notifications_unread_repository.dart';
import 'package:conferenceapp/profile/auth_repository.dart';
import 'package:conferenceapp/profile/favorites_repository.dart';
import 'package:conferenceapp/profile/user_repository.dart';
import 'package:conferenceapp/talk/talk_page.dart';
import 'package:conferenceapp/ticket/bloc/bloc.dart';
import 'package:conferenceapp/ticket/repository/ticket_repository.dart';
import 'package:dynamic_theme/dynamic_theme.dart';
import 'package:feature_discovery/feature_discovery.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    Key key,
    this.title,
    this.sharedPreferences,
    this.firebaseMessaging,
  }) : super(key: key);

  final String title;
  final SharedPreferences sharedPreferences;
  final FirebaseMessaging firebaseMessaging;

  @override
  Widget build(BuildContext context) {
    final orange = Color.fromARGB(255, 240, 89, 41);
    final blue = Color.fromARGB(255, 33, 153, 227);
    return DynamicTheme(
      defaultBrightness: Brightness.light,
      data: (brightness) => ThemeData(
        primaryColor: blue,
        scaffoldBackgroundColor: brightness == Brightness.light
            ? Colors.grey[100]
            : Colors.grey[850],
        accentColor: orange,
        toggleableActiveColor: orange,
        dividerColor:
            brightness == Brightness.light ? Colors.white : Colors.white54,
        brightness: brightness,
        fontFamily: 'PTSans',
        bottomAppBarTheme: Theme.of(context).bottomAppBarTheme.copyWith(
              elevation: 0,
            ),
        pageTransitionsTheme: PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        iconTheme: Theme.of(context).iconTheme.copyWith(color: orange),
      ),
      themedWidgetBuilder: (context, theme) {
        return VariousProviders(
          sharedPreferences: sharedPreferences,
          firebaseMessaging: firebaseMessaging,
          child: RepositoryProviders(
            child: BlocProviders(
              child: ChangeNotifierProviders(
                child: FeatureDiscovery(
                  child: MaterialApp(
                      title: title,
                      theme: theme,
                      navigatorKey: navigatorKey,
                      navigatorObservers: [
                        FirebaseAnalyticsObserver(analytics: analytics),
                      ],
                      home: HomePage(title: title)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final navigatorKey = GlobalKey<NavigatorState>();

class VariousProviders extends StatefulWidget {
  final Widget child;
  final SharedPreferences sharedPreferences;
  final FirebaseMessaging firebaseMessaging;

  const VariousProviders({
    Key key,
    this.child,
    this.sharedPreferences,
    this.firebaseMessaging,
  }) : super(key: key);

  @override
  _VariousProvidersState createState() => _VariousProvidersState();
}

class _VariousProvidersState extends State<VariousProviders> {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    widget.firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> message) async {
        print("onMessage: $message");
      },
      // onBackgroundMessage: (Map<String, dynamic> message) async {
      //   print("onBackgroundMessage: $message");
      // },
      onLaunch: (Map<String, dynamic> message) async {
        print("onLaunch: $message");
      },
      onResume: (Map<String, dynamic> message) async {
        print("onResume: $message");
      },
    );
    widget.firebaseMessaging.subscribeToTopic('notifications');
    widget.firebaseMessaging.requestNotificationPermissions();
    final reminders = widget.sharedPreferences.getBool('reminders');
    if (reminders == null) {
      widget.sharedPreferences.setBool('reminders', true);
    }

    flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
    // initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
    var initializationSettingsAndroid =
        new AndroidInitializationSettings('app_icon');
    var initializationSettingsIOS = IOSInitializationSettings(
        onDidReceiveLocalNotification: onDidReceiveLocalNotification);
    var initializationSettings = InitializationSettings(
        initializationSettingsAndroid, initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onSelectNotification: onSelectNotification,
    );
  }

  Future onDidReceiveLocalNotification(
      int id, String title, String body, String payload) {
    print(id);
    print(title);
    print(body);
    print(payload);
    return Future.value(true);
  }

  Future onSelectNotification(String payload) async {
    if (payload != null) {
      debugPrint('notification payload: ' + payload);
    }

    navigatorKey.currentState.push(
      MaterialPageRoute(
        builder: (context) => TalkPage(payload),
        settings: RouteSettings(name: 'agenda/$payload'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(
          value: widget.sharedPreferences,
        ),
        Provider<FirebaseMessaging>.value(
          value: widget.firebaseMessaging,
        ),
        Provider<FlutterLocalNotificationsPlugin>.value(
          value: flutterLocalNotificationsPlugin,
        ),
      ],
      child: widget.child,
    );
  }
}

class BlocProviders extends StatelessWidget {
  const BlocProviders({Key key, this.child}) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AgendaBloc>(
          create: (BuildContext context) =>
              AgendaBloc(RepositoryProvider.of<TalkRepository>(context))
                ..add(InitAgenda()),
        ),
        BlocProvider<TicketBloc>(
          create: (BuildContext context) =>
              TicketBloc(RepositoryProvider.of<TicketRepository>(context))
                ..add(FetchTicket()),
        ),
      ],
      child: child,
    );
  }
}

class RepositoryProviders extends StatelessWidget {
  final Widget child;

  const RepositoryProviders({Key key, @required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sharedPreferences = Provider.of<SharedPreferences>(context);

    return RepositoryProvider(
      create: (_) => AuthRepository(FirebaseAuth.instance),
      child: RepositoryProvider(
        create: _userRepositoryBuilder,
        child: RepositoryProvider<TalkRepository>(
          create: _talksRepositoryBuilder,
          // create: (_) => FirestoreTalkRepository(),
          child: RepositoryProvider(
            create: _favoritesRepositoryBuilder,
            child: RepositoryProvider(
              create: _ticketRepositoryBuilder,
              child: RepositoryProvider(
                create: _notificationsRepositoryBuilder,
                child: RepositoryProvider(
                  create: (context) =>
                      _notificationsUnreadStatusRepositoryBuilder(
                          context, sharedPreferences),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  UserRepository _userRepositoryBuilder(BuildContext context) {
    return UserRepository(
      RepositoryProvider.of<AuthRepository>(context),
      Firestore.instance,
    );
  }

  FavoritesRepository _favoritesRepositoryBuilder(BuildContext context) {
    return FavoritesRepository(
      RepositoryProvider.of<TalkRepository>(context),
      RepositoryProvider.of<UserRepository>(context),
    );
  }

  FirestoreNotificationsRepository _notificationsRepositoryBuilder(
      BuildContext context) {
    return FirestoreNotificationsRepository(Firestore.instance);
  }

  AppNotificationsUnreadStatusRepository
      _notificationsUnreadStatusRepositoryBuilder(
          BuildContext context, SharedPreferences sharedPreferences) {
    return AppNotificationsUnreadStatusRepository(
      RepositoryProvider.of<FirestoreNotificationsRepository>(context),
      sharedPreferences,
    );
  }

  TicketRepository _ticketRepositoryBuilder(BuildContext context) {
    return TicketRepository(
      RepositoryProvider.of<UserRepository>(context),
    );
  }

  TalkRepository _talksRepositoryBuilder(BuildContext context) {
    return ReactiveTalksRepository(
      repository: ContentfulTalksRepository(
        client: ContentfulClient(
          appConfig.contentfulSpace,
          appConfig.contentfulApiKey,
        ),
        fileStorage: FileStorage(
            'talks', () => Directory.systemTemp.createTemp('talks_')),
      ),
    );
  }
}

class ChangeNotifierProviders extends StatelessWidget {
  const ChangeNotifierProviders({Key key, this.child}) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sharedPreferences = Provider.of<SharedPreferences>(context);
    final agendaMode = sharedPreferences.getString('agenda_mode');
    final compactMode = agendaMode == 'compact' || agendaMode == null;

    return ChangeNotifierProvider<AgendaLayoutHelper>(
      create: (_) => AgendaLayoutHelper(compactMode),
      child: child,
    );
  }
}
