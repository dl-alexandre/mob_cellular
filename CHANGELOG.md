# Changelog

## 0.2.0

- Added Telemetry events for send, receive, and error paths.
- Switched broadcast delivery to concurrent `Task.async_stream/3` with
  per-recipient result reporting.
- Changed payload budgeting to measure JSON-encoded envelope bytes.
- Added `Mob.Cellular.PushBridge.serialized_size/1`.
- Added `child_spec/1` for direct supervision.
- Hardened push client exception and throw handling.
- Added GitHub Actions CI, Credo, Dialyxir, `mix check`, and `CONTRIBUTING.md`.
- Expanded `PushBridge` tests for delivery, broadcast, payload limits, and
  Telemetry assertions.
- Added an attached-hardware validation harness and documentation that records
  local bridge/fallback checks plus FCM/APNs readiness blockers.

## 0.1.0

- Initial push-based cellular fallback transport.
- Added plugin manifest for FCM/APNs setup.
- Added carrier/config validation and docs.
