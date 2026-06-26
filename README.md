# BlindFriend

**BlindFriend** is a Flutter companion app built to help visually impaired people move through their day with more independence — built around voice-first, hands-free interaction at every step. The app connects blind users with sighted volunteers for real-time help, while also giving them tools to handle everyday tasks (shopping, navigating, avoiding obstacles) on their own.

The app supports three kinds of users, each with their own experience:

- **Blind / visually impaired users** — request help, get live assistance with shopping and navigation, and track requests, all primarily by voice.
- **Volunteers** — get notified of nearby help requests, accept them, and assist blind users in person or remotely.
- **Admins** — manage volunteer verification, monitor activity, and oversee the platform from a web/desktop dashboard.

## Features

### For blind / visually impaired users
- **Voice-first navigation** — every screen can be operated by speech; the app also speaks back instructions, confirmations, and alerts via text-to-speech.
- **Request Help** — describe what you need and your request is sent to nearby volunteers automatically. Your location is captured via GPS (no manual entry needed) so volunteers can find you.
- **Shopping Helper** — scan product barcodes to hear the product name, brand, ingredients, allergens, and nutrition information read aloud.
- **Obstacle Detection** — real-time camera-based object detection with spoken alerts about what's ahead and how close it is.
- **Tactile Path Guidance** — uses the camera to follow tactile paving (the textured strips on sidewalks), distinguishing directional bars from warning domes, and speaks turn-by-turn guidance.
- **Track Requests** — check the status of help requests, see which volunteer accepted, and rate/report a volunteer afterwards.
- **Notifications** — unread notifications (e.g. request accepted, volunteer arriving) are read aloud automatically when the app opens.
- **Accessibility Settings** — adjustable font size and high-contrast mode, layered on top of the voice-first design.

### For volunteers
- View and accept pending help requests from blind users nearby.
- See the requester's live location on a map once a request is accepted, with a one-tap call as a fallback if they can't find them.
- Track volunteering history and view ratings received from blind users.
- Complete training modules before taking on requests.

### For admins
- Web/desktop dashboard with an at-a-glance overview: volunteer counts, ratings, request activity, and live/recent help-request locations.
- Review and approve/reject pending volunteer applications.
- Manage registered users and volunteers, with search, sort, and filtering.
- View reports submitted against volunteers.

## Tech stack

- **Flutter** (Dart) — single codebase for Android, iOS, and desktop (Windows tested; macOS/Linux buildable)
- **Firebase** — Authentication, Cloud Firestore (data), used as the backend throughout
- **speech_to_text** / **flutter_tts** — voice input and spoken feedback
- **camera** + **google_mlkit_object_detection** — real-time obstacle detection
- **mobile_scanner** — barcode scanning, paired with the [Open Food Facts](https://world.openfoodfacts.org/) API for product lookups
- **geolocator** + **flutter_map** (OpenStreetMap tiles) — GPS capture and map display
- **url_launcher** — one-tap phone calls between volunteers and blind users

## Platform support

Camera-dependent features only run where the underlying plugins ship native support:

| Feature | Android | iOS | Web | Windows / macOS / Linux desktop |
|---|---|---|---|---|
| Voice commands & TTS | ✅ | ✅ | ✅ | ✅ |
| Help requests, tracking, admin dashboard | ✅ | ✅ | ✅ | ✅ |
| Barcode scanning | ✅ | ✅ | ✅ | ❌ |
| Obstacle detection | ✅ | ✅ | ❌ | ❌ |
| Tactile path guidance | ✅ | ✅ | ❌ | ❌ |

The app detects platform support at runtime and shows a friendly message instead of a broken camera view where a feature isn't available.

## Getting started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ≥ 3.4.0)
- A Firebase project with **Authentication** and **Cloud Firestore** enabled
- For Android/iOS builds: Android Studio / Xcode set up as usual for Flutter

### Setup

```bash
git clone https://github.com/dotrovi/BlindFriend.git
cd BlindFriend
flutter pub get
```

This project uses [FlutterFire](https://firebase.flutter.dev/) for Firebase configuration. `lib/firebase_options.dart` is already checked in for the project's Firebase backend; if you're pointing this at your **own** Firebase project, regenerate it with:

```bash
flutterfire configure
```

### Run

```bash
flutter run                # pick a connected device/emulator
flutter run -d windows      # run the desktop build
flutter run -d chrome       # run in a browser
```

### Useful Firestore collections

| Collection | Purpose |
|---|---|
| `users` | All accounts (blind users and volunteers), keyed by uid |
| `volunteers` | Volunteer applications/status, specialties, ratings |
| `help_requests` | Help requests, including GPS coordinates and status |
| `notifications/{uid}/messages` | Per-user in-app notifications |
| `admins` | Admin accounts |
| `reports` | Reports filed against volunteers |

## Project structure

```
lib/
  main.dart                     # App entry point and routing
  login_page.dart, register_page.dart, forgot_password_page.dart
  blind_home_page.dart          # Blind user home + voice command routing
  shopping_helper_page.dart, barcode_scanner_page.dart
  obstacle_detection_page.dart, tactile_path_page.dart
  blind_send_help_request.dart, blind_track_help_request.dart
  blind_notifications_page.dart, blind_rate_volunteer_page.dart, blind_report_volunteer_page.dart
  volunteer_home_page.dart, volunteer_received_request.dart
  volunteer_profile_page.dart, volunteer_training_page.dart, volunteer_history_page.dart
  admin_login_page.dart, admin_dashboard_page.dart, admin_overview_page.dart
  admin_users_page.dart, admin_volunteers_page.dart, pending_verifications_page.dart, admin_reports_page.dart
  services/                     # Firebase, admin, notification, and accessibility helpers
  theme/                        # Shared color palette
```

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` before opening a PR.
