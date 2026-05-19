==============================================================================
PROJECT: Smart App for Ambulance Driver (FYP)
==============================================================================

SYSTEM OVERVIEW (reduced scope — pilot)
---------------------------------------
Three client surfaces share one Supabase backend:

1. Clinic web portal (React) — dispatch, live driver map, mission records
2. Driver mobile app (Flutter) — assignments, GPS, status, external navigation
3. Patient / bystander mobile app (Flutter) — report emergency, track ambulance, chat

Pilot model: one registered clinic, one ambulance, up to two driver accounts.

NOT in this scope: system-admin dashboard, in-app lane guidance, automatic
nearest-ambulance assignment, multi-fleet national dispatch.

------------------------------------------------------------------------------
1. PREREQUISITES
------------------------------------------------------------------------------
- Node.js (LTS)
- Flutter SDK (see pubspec.yaml for Dart SDK)
- Supabase project (cloud)
- Google Maps Platform API key (Maps JavaScript + Maps SDK for mobile)

------------------------------------------------------------------------------
2. DATABASE (Supabase)
------------------------------------------------------------------------------
1. Create a Supabase project at https://supabase.com
2. In SQL Editor, run scripts under web-app/supabase/ (start with
   rebuild_smart_ambulance.sql for a clean schema). For an existing DB without
   bed columns, run web-app/supabase/clinics_bed_availability.sql.
   For advance / bedridden bookings, run web-app/supabase/bookings_scheduled.sql
   and web-app/supabase/bookings_scheduled_driver_ack.sql.
3. Create Storage buckets as noted in that script (mission-evidence,
   patient-reports, etc.).
4. Copy Supabase URL and anon key into:
   - mobile-app/lib/main.dart
   - web-app/.env (see web-app/.env.example)

------------------------------------------------------------------------------
3. CLINIC WEB PORTAL (React)
------------------------------------------------------------------------------
cd web-app
npm install
cp .env.example .env   (fill VITE_SUPABASE_* and Google Maps key)
npm start

Opens http://localhost:3000 — register a clinic or sign in as clinic staff.

------------------------------------------------------------------------------
4. MOBILE APP (Flutter — driver + patient)
------------------------------------------------------------------------------
cd mobile-app
flutter pub get
flutter run

On first launch, choose role:
  - Ambulance driver — sign in with credentials created by the clinic portal
  - Patient / bystander — register in-app, then report and track

Drivers are added only from the clinic web portal (not self-registration on mobile).

Supabase keys are in lib/main.dart (use the same project as the web app).

------------------------------------------------------------------------------
5. TROUBLESHOOTING
------------------------------------------------------------------------------
- Maps blank on web: check Google Maps API key and billing in Cloud Console.
- Patient address search 403: Flutter calls Places over HTTP, so the key must NOT
  use "HTTP referrers" (web) or "Android apps" (native SDK only). In Cloud Console
  edit the MOBILE key: Application restrictions = None; API restrictions = Places API
  (New) + Geocoding API. Use a separate key with "Android apps" + SHA-1 only in
  AndroidManifest.xml for native Maps SDK. If Google still blocks, the app uses
  OpenStreetMap (map pin + GPS still work).
- Driver not receiving jobs: driver must be Online (Available); clinic must assign
  or link a patient report to a booking.
- Patient cannot sign in: patient profile must exist in Supabase for that auth user.

For full schema and RLS notes, see web-app/supabase/*.sql

==============================================================================
