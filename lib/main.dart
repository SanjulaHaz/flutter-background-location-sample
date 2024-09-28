import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Background Location & Socket.io',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  IO.Socket? socket;
  StreamSubscription<Position>? positionStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connectSocket();
    requestLocationPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    positionStream?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  Future<void> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permission denied.');
      }
    }

    if (permission == LocationPermission.whileInUse) {
      // Request "Always Allow" permission after "When in Use" is granted
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permission permanently denied. Please enable it from settings.');
    }
    print(await Geolocator.checkPermission());
    if (await Geolocator.checkPermission() == LocationPermission.always) {
      // Start location updates once permission is granted
      startLocationUpdates();
    } else if (await Geolocator.requestPermission() != LocationPermission.always) {
      return Future.error('Background location permission not granted.');
    }
  }

  void connectSocket() {
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
    });

    socket?.onConnect((_) {
      print('Connected to socket server');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      // App is either in the foreground or minimized, start location updates
      startLocationUpdates();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      // App is closed or detached, stop location updates
      stopLocationUpdates();
    }
  }

  void startLocationUpdates() {
    if (positionStream == null || positionStream!.isPaused) {
      positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).listen((Position position) {
        print("Location: ${position.latitude}, ${position.longitude}");

        // Send location data to the socket server
        socket?.emit('location', {
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
      });
    }
  }

  void stopLocationUpdates() {
    positionStream?.pause();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Background Location & Socket.io"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            FlutterBackgroundService().invoke("startSocketService");
          },
          child: Text("Start Background Location"),
        ),
      ),
    );
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // This background service handles socket and location updates when the app is in the background
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
