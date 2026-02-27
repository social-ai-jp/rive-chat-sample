# Rive Avatar Integration — Issues for Expert Review

## Screenshot Analysis (confirmed 2026-02-27)

The Rive editor screenshot confirms:

- **Data panel → Enums → `Enum`** with values `Idle` and `Talking` — this is a **standalone Enum type definition**, not inside a ViewModel
- **Inputs panel** (bottom-left of Animate tab) is **completely empty** — State Machine 1 has zero SM inputs
- **View Models** section is separate and appears empty

This definitively explains why `getNumberInput('Enum')` returns null: the `Enum` is only a type *definition* in the Data panel. It is not wired as a state machine input that Flutter can control.

### Recommended fix (Rive editor)
In the Animate tab → State Machine 1 → **Inputs panel**:
1. Click `+` → **Number** → name it `State`
2. Wire transitions: `Idle → Talking` when `State == 1`, `Talking → Idle` when `State == 0`
3. Re-export `.riv`

The Flutter code already tries `getNumberInput('State')` as first candidate — no Flutter code changes needed after the `.riv` is updated.

### Alternative: Use the Enum type as a ViewModel property
If you want to keep using the `Enum` type:
1. Create a **ViewModel** in the Data panel
2. Add a property of type `Enum` to it (using the existing `Enum` type)
3. Bind that ViewModel property to the state machine transition condition via Data Binding
4. In Flutter, access via the ViewModel instance API (more complex)

The Number SM input approach above is simpler and recommended.

---

## Context

Flutter app (`rive ^0.13.20`) with a `.riv` file (`andrew_avatar.riv`) that contains:

- **Artboard-level Rive Scripts** — eye tracking (follows mouse/pointer) and idle body sway
- **State Machine named "State Machine 1"** — has a **Number input called `Enum`** where:
  - `0` = Idle
  - `1` = Talking (lip sync / speaking animation)

The avatar is displayed using `RiveAnimation.asset` in a Flutter widget. An ElevenLabs voice agent drives the `Enum` input via an `onModeChange` callback.

---

## Issue 1 — Missing eye iris / broken scripts

### Symptom
One eye iris disappears. The eye-tracking and idle-sway scripts (which are Rive Scripts on the artboard, not part of the State Machine) do not run.

### What we tried
1. Initially used `RiveAnimation.asset(stateMachines: ['State Machine 1'], onInit: _onRiveInit)` — this creates and attaches a `StateMachineController` internally.
2. Inside `_onRiveInit`, we also called `StateMachineController.fromArtboard(artboard, 'State Machine 1')` followed by `artboard.addController(controller)` — suspecting this double-registers the SM and corrupts internal state.
3. Removed `stateMachines:` param and only used manual `fromArtboard` + `addController` in `_onRiveInit` — scripts still appear broken.

### Current `_onRiveInit` code
```dart
void _onRiveInit(Artboard artboard) {
  final controller =
      StateMachineController.fromArtboard(artboard, 'State Machine 1');
  if (controller == null) {
    debugPrint('[Rive] "State Machine 1" not found');
    return;
  }

  artboard.addController(controller);
  _riveController = controller;

  for (final input in controller.inputs) {
    debugPrint('[Rive] input: "${input.name}" (${input.runtimeType})');
  }

  _enumInput = controller.getNumberInput('Enum');
  if (_enumInput != null) {
    _enumInput!.value = 0;
  }
}
```

### Questions for expert
- Is there something specific about Rive Scripts + State Machines coexisting that requires a different setup? E.g. do scripts need a separate `SceneController` or a specific ordering of controller registration?
- Does `fromArtboard` re-use an existing controller if already registered, or always create a new one?
- Does `RiveAnimation.asset` with no `stateMachines:` param still auto-activate scripts?

---

## Issue 2 — `Enum` input not triggering the Speaking animation

### Symptom
The breathing/idle animation loops correctly. When we set `_enumInput?.value = 1`, the avatar does **not** visibly switch to a talking/speaking animation. Setting it back to `0` also has no visible effect. The status bar in the Flutter UI correctly reflects the speaking state — so the ElevenLabs callback fires — but the Rive SM transition does not happen.

### Speaking trigger code
```dart
// Called from ElevenLabs onModeChange callback:
void _setSpeaking(bool speaking) {
  if (_isSpeaking == speaking) return;
  _isSpeaking = speaking;
  _enumInput?.value = speaking ? 1 : 0;
  debugPrint('[Bridge] Enum → ${speaking ? 1 : 0}');
  if (mounted) setState(() {});
}
```

A debug panel was added to manually set the Enum value (0–3) via buttons and a slider to test without ElevenLabs being active.

### Questions for expert
- In Rive, is a **Number** the correct input type for an "Enum-like" state switch? Or should this be a separate Boolean per state, or a proper Rive Enum type?
- Are there conditions in the State Machine (e.g. transition guards, entry conditions) that might prevent the state from switching even when the input value changes?
- Is `SMINumber` the right Swift/Dart type to use for this, or should it be `SMIInput<double>`?

---

## Issue 3 — Eye tracking with mouse (Web/Chrome)

### Context
The `.riv` scripts include eye tracking that should follow the pointer/mouse. This is expected to work on web (Chrome) via `flutter run -d chrome`.

### Symptom
Eye tracking does not respond to mouse movement on web. Unclear if this is:
- The scripts not running at all (related to Issue 1)
- A web-specific pointer event issue in Flutter Web + Rive
- A missing `RiveAnimation` configuration for pointer/hit testing

### Questions for expert
- Does the Rive Flutter package pass pointer events to artboard scripts automatically, or does it need explicit `PointerListener` / `MouseRegion` wrapping?
- Is there a known limitation with Rive Scripts + Flutter Web?

---

## Environment

| Package | Version |
|---------|---------|
| `rive` | `^0.13.20` (resolved `0.13.20`) |
| `elevenlabs_agents` | `^0.3.0` (resolved `0.3.1`) |
| `permission_handler` | `^11.0.0` |
| Flutter | latest stable |
| Target platforms | Android, iOS, Web (Chrome) |

---

## Full `RiveAnimation.asset` widget code

```dart
Expanded(
  flex: 4,
  child: ClipRect(
    child: Transform.scale(
      scale: 2.0,                          // zoom level
      alignment: Alignment(0.0, -1.2),     // pan to upper body
      child: RiveAnimation.asset(
        'assets/andrew_avatar.riv',
        fit: BoxFit.contain,
        onInit: _onRiveInit,
        // NOTE: stateMachines: NOT passed here — we register manually in onInit
      ),
    ),
  ),
),
```
