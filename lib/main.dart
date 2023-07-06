import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geojson_vi/geojson_vi.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as PH;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

void main() {
  HttpOverrides.global = MyHttpOverrides();

  Map<PH.Permission, PH.PermissionStatus> statuses;
  [
    PH.Permission.location,
    PH.Permission.storage,
  ].request().then((value) {
    statuses = value;
    print(statuses[PH.Permission.location]);
  });

  runApp(const RedLineApp());
}

class RedLineApp extends StatelessWidget {
  const RedLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Red Line',
      theme: ThemeData.dark(),
      home: const RedLineHome(),
    );
  }
}

class RedLineHome extends StatefulWidget {
  const RedLineHome({super.key});

  @override
  State<RedLineHome> createState() => _RedLineHomeState();
}

class _RedLineHomeState extends State<RedLineHome> {
  late Socket socket;
  double? latitude;
  double? longitude;

  int _selectedPageIndex = 0;
  static const Color _textColor = Colors.redAccent;

  static const List<Widget> _pages = <Widget>[
    RedLineMapPage(),
    Icon(
      Icons.star_outline,
      size: 150,
    ),
    Icon(
      Icons.info_outlined,
      size: 150,
    ),
  ];

  @override
  void initState() {
    super.initState();

    initSocket().then((value) => initGeolocator(value));
  }

  Future<Socket> initSocket() async {
    Socket socket = io(
        'https://10.0.2.2:8080',
        OptionBuilder().setAuth({'token': 'jzC9r22kBZAO'})
            //.enableAutoConnect()
            .setTransports(
                ['websocket']).build()); // 10.0.2.2 because android emulator

    socket.connect();

    socket.onConnecting((data) => {print('Connecting...')});

    socket.onConnect((data) => {print('Connected with id: ${socket.id}')});

    socket.onConnectError((data) => print('Connection Error: ${data}'));

    return socket;
  }

  void initGeolocator(Socket socket) {
    Location location = Location();
    location.enableBackgroundMode(enable: true);
    location.changeSettings(interval: 750);

    location.onLocationChanged.listen((LocationData currentLocation) {
      print(currentLocation == null
          ? 'Unknown'
          : '${currentLocation.latitude.toString()}, ${currentLocation.longitude.toString()}');
      socket.emit('location-update', currentLocation.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Red Line',
            style: GoogleFonts.montserrat(
                textStyle: const TextStyle(color: _textColor))),
      ),
      body: IndexedStack(
        index: _selectedPageIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        //type: BottomNavigationBarType.shifting,
        selectedFontSize: 20,
        selectedIconTheme: const IconThemeData(color: _textColor, size: 40),
        selectedItemColor: _textColor,
        selectedLabelStyle: GoogleFonts.montserrat(
            textStyle: const TextStyle(
                color: _textColor, fontWeight: FontWeight.bold)),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            label: 'Challenges',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            label: 'Game Info',
          ),
        ],
        currentIndex: _selectedPageIndex,
        onTap: _onNavigationBarTapped,
      ),
    );
  }

  void _onNavigationBarTapped(int index) {
    setState(() {
      _selectedPageIndex = index;
    });
  }
}

class RedLineMapPage extends StatefulWidget {
  const RedLineMapPage({Key? key}) : super(key: key);

  @override
  State<RedLineMapPage> createState() => _RedLineMapPageState();
}

class _RedLineMapPageState extends State<RedLineMapPage> {
  static const LatLng _mapCenter = LatLng(42.356212, -71.088100);

  static const CameraPosition _initialCameraPosition =
      CameraPosition(target: _mapCenter, zoom: 10.0, tilt: 0, bearing: 0);
  CameraPosition _currentCameraPosition = _initialCameraPosition;

  late GoogleMapController _mapController;
  late GoogleMap _googleMap;
  late String _mapStyle;

  bool _bikeStationMarkersVisible = true;
  late BitmapDescriptor _bikeStationIcon;
  final List<double> _bikeStationZoomLimit = [14.0, 21.0];
  Set<Marker> _bikeStationMarkers = <Marker>{};

  Set<Marker> _markers = <Marker>{};

  @override
  void initState() {
    super.initState();

    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(size: Size(48, 48)),
            'assets/bike_station_icon_small.png')
        .then((value) {
      _bikeStationIcon = value;
    });

    rootBundle.loadString('assets/map_style.json').then((string) {
      _mapStyle = string;
    });
    rootBundle.loadString('assets/Blue_Bike_Stations.geojson').then((string) {
      _parseBikeStationGeoJSON(string);
    });
  }

  // Bike GeoJSON
  void _parseBikeStationGeoJSON(String string) async {
    final GeoJSONFeatureCollection geoFeatures =
        GeoJSON.fromJSON(string) as GeoJSONFeatureCollection;
    final Set<Marker> geoMarkers = <Marker>{};

    for (GeoJSONFeature? feature in geoFeatures.features) {
      Marker marker = Marker(
        markerId: MarkerId(feature?.properties?['Number']),
        infoWindow: InfoWindow(title: feature?.properties?['Name']),
        icon: _bikeStationIcon,
        position: LatLng(feature?.properties?['Latitude'],
            feature?.properties?['Longitude']),
      );
      geoMarkers.add(marker);
    }

    setState(() {
      _bikeStationMarkers = geoMarkers;
      _updateBikeStationVisibility();
    });
  }

  void _onCameraMoveEnd() {
    _updateBikeStationVisibility();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: GoogleMap(
        initialCameraPosition: _initialCameraPosition,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (GoogleMapController controller) {
          _mapController = controller;
          _mapController.setMapStyle(_mapStyle);
        },
        onCameraMove: (CameraPosition position) {
          _currentCameraPosition = position;
        },
        onCameraIdle: _onCameraMoveEnd,
        mapType: MapType.normal,
        markers: _markers,
      ),
    );
  }

  void _updateBikeStationVisibility() {
    bool shouldBikeStationMarkersBeVisible =
        (_currentCameraPosition.zoom > _bikeStationZoomLimit[0] &&
            _currentCameraPosition.zoom < _bikeStationZoomLimit[1]);

    if (_bikeStationMarkersVisible == true &&
        shouldBikeStationMarkersBeVisible == false) {
      setState(() {
        _markers.removeAll(_bikeStationMarkers);
      });
    } else if (_bikeStationMarkersVisible == false &&
        shouldBikeStationMarkersBeVisible == true) {
      setState(() {
        _markers.addAll(_bikeStationMarkers);
      });
    }

    _bikeStationMarkersVisible = shouldBikeStationMarkersBeVisible;
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
