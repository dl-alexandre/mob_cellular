# Hardware Validation

`mob_cellular` has two layers of validation:

- Package-level behavior: envelope handling, payload limits, Telemetry, push
  client delegation, and fallback selection.
- Device-level delivery: native Android/iOS push registration, provider
  delivery through FCM/APNs, and handoff into
  `Mob.Cellular.PushBridge.receive_push/2`.

Run the local validation harness:

```sh
mix run scripts/hardware_validation.exs
```

The script writes JSON and Markdown evidence under `artifacts/hardware/`.

## Current Gates

The harness marks local bridge and fallback checks as pass/fail. It marks real
FCM/APNs hardware delivery as blocked until the following are present:

- Real Firebase `google-services.json`.
- Android native callback that hands the mob cellular envelope into on-device
  BEAM and `receive_push/2`.
- APNs team/key/bundle configuration.
- iOS native callback that hands the mob cellular envelope into on-device BEAM
  and `receive_push/2`.
- Server-side `push_client` mapping peer ids to platform push tokens.

## Expected Device Matrix

- Android FCM foreground and background data push.
- iOS APNs foreground and background push.
- Android-to-iOS logical delivery through the shared push client.
- iOS-to-Android logical delivery through the shared push client.
- Fallback routing where BLE, WiFi, and mesh are unavailable and cellular is
  selected.
