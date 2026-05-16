/// Same key as web `REACT_APP_GOOGLE_MAPS_API_KEY` / native Maps SDK.
/// Override: `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key`
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: 'AIzaSyBrCE1k3ZRrwa8i44A1zz5QWDE0Vc107ec',
);

bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;
