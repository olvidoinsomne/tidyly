# Tidyly (SwiftUI — iOS & macOS)

A native SwiftUI cleaning & home-care app, targeting **both iOS and macOS** from a single Swift codebase.

## Requirements

- **Xcode 15+** (on macOS)
- **Swift 5.9+**
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`

## Setup

1. Install XcodeGen (one-time):
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd tidyly-swift
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open Tidyly.xcodeproj
   ```

4. Select the **Tidyly_iOS** scheme and your connected iPhone as the run destination.
5. In **Tidyly_iOS > Signing & Capabilities**, enable automatic signing and select your Apple development team.
6. If prompted on the iPhone, enable Developer Mode and trust the developer certificate, then press **Cmd+R** to install and run.

## Supabase Configuration

The app reads Supabase credentials from a `Secrets.swift` file (gitignored). Create it before building:

```swift
// Tidyly/Services/Secrets.swift
enum Secrets {
    static let supabaseURL = "https://<your-project>.supabase.co"
    static let supabaseAnonKey = "<your-anon-key>"
}
```

Use the same `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` values from the Expo project's `.env` file — the database schema is already migrated and shared.

## Project Structure

```
tidyly-swift/
├── project.yml              # XcodeGen project definition
└── Tidyly/
    ├── TidylyApp.swift      # App entry point + tab navigation
    ├── Models/              # Codable data models
    ├── Services/            # Supabase client, database service, secrets
    ├── Theme/               # Colors, spacing, typography
    ├── Components/          # Reusable SwiftUI views
    └── Screens/             # Today, Rooms, Schedule, Stats, Settings
```

## Features

- Today's tasks with progress ring and one-tap completion
- Room management with per-room progress and task editing
- Weekly schedule calendar
- Analytics: streaks, completion charts, per-room breakdown
- Settings: household name, preferences, data export
