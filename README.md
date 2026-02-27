# VTuber Chat

Rive avatar + ElevenLabs Conversational AI voice agent.

## Setup

### 1. Create Flutter project

Since this is just the source files, you need to create the Flutter project scaffold first:

```bash
flutter create vtuber_chat --platforms=android,ios
```

Then copy the following into the created project:
- Replace `lib/` with the provided `lib/` directory
- Replace `pubspec.yaml` with the provided one
- Copy `assets/andrew_avatar.riv` into `assets/`
- Merge the AndroidManifest.xml permissions into your generated one

### 2. Install dependencies

```bash
cd vtuber_chat
flutter pub get
```

### 3. Platform config

**Android** — in `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

Add these permissions to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

**iOS** — add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice conversations</string>
```

In `ios/Podfile`, set:
```ruby
platform :ios, '13.0'
```

### 4. ElevenLabs Agent

1. Go to https://elevenlabs.io/agents
2. Create an agent with Claude as the LLM
3. Configure voice, system prompt, etc.
4. The agent ID is already set in `conversation_screen.dart`

### 5. Run

```bash
flutter run
```

## How it works

- ElevenLabs SDK handles mic → STT → Claude → TTS → speaker
- `onModeChange` callback detects when agent starts/stops speaking
- Rive state machine `Enum` input toggles between Idle (0) and Talking (1)
- Chat transcripts shown below the avatar

## Architecture

```
┌─────────────────────────────────────┐
│           Flutter App               │
│                                     │
│  ┌─────────────┐  ┌──────────────┐  │
│  │ Rive Avatar  │  │ ElevenLabs   │  │
│  │              │  │ SDK          │  │
│  │ Enum input:  │◄─│              │  │
│  │  0 = Idle    │  │ onModeChange │  │
│  │  1 = Talking │  │ isSpeaking   │  │
│  └─────────────┘  └──────────────┘  │
│                         ▲ │         │
│                   mic ──┘ └── audio  │
└─────────────────────────────────────┘
            ▲         │
            │ WebRTC  │
            ▼         ▼
   ┌──────────────────────┐
   │  ElevenLabs Agent    │
   │  STT → Claude → TTS  │
   └──────────────────────┘
```
