# SmsGo

Bulk SMS marketing app for Android. Promote your business by sending personalized messages to leads using dual-SIM support with real-time monitoring.

## Features

- **Bulk SMS Sending** — Send personalized messages to thousands of leads with configurable intervals and rest periods
- **Dual-SIM Support** — Send from SIM 1, SIM 2, or alternate between both
- **Campaign Management** — Organize leads and messages into campaigns
- **Contact Import** — Import leads from Excel (.xlsx) files with field mapping
- **Message Templates** — Create message groups with `{username}` placeholder personalization
- **Link Breaking** — Automatically break URLs to comply with network filtering (Globe, Smart, DITO)
- **Progress Monitoring** — Receive SMS updates to a monitor number after every N messages
- **Background Sending** — Continue sending while the app is in the background via foreground service
- **Conversation Tracking** — View sent messages per lead with delivery status
- **SMS History Import** — Import existing SMS from the Android message database
- **Theme Support** — Light, dark, and system theme modes
- **License System** — Device-locked license validation via Supabase

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Local Database | SQLite (sqflite) |
| Backend / Auth | Supabase |
| State Management | Provider |
| Background Service | flutter_background_service |
| Notifications | flutter_local_notifications |
| Native SMS | Android SmsManager via MethodChannel |

## Permissions

The app requires the following Android permissions:

- `SEND_SMS` — Sending SMS messages
- `READ_SMS` — Importing SMS history
- `RECEIVE_SMS` — Receiving delivery reports
- `READ_PHONE_STATE` — SIM detection
- `FOREGROUND_SERVICE` — Background sending
- `POST_NOTIFICATIONS` — Progress notifications

## Project Structure

```
lib/
├── core/           # Constants, permissions, shared widgets
├── database/       # SQLite database, migrations
├── features/       # UI screens (auth, campaign, messaging, settings)
├── models/         # Data models
├── providers/      # State management (Provider)
├── repositories/   # Database access layer
├── routes/         # Navigation routing
├── services/       # Business logic (SMS, notifications, background)
├── main.dart       # App entry point
└── splash_screen.dart
```
