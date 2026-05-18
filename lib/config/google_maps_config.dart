/// Android-restricted key (Places / Geocoding over HTTP). Web portal uses a separate key in `web-app/.env`.
/// Override: `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key`
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: 'AIzaSyBHJa1QP-iYRp_mhx-8TK1QEmNnVt4Vz9g',
);

bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;
