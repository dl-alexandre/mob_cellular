# Cost and Battery

## Push

FCM and APNs are generally the lowest-battery option because delivery is
coordinated by the operating system. The transport should keep payloads small
and avoid periodic polling.

## SMS

SMS can incur per-message cost, has strict payload limits, and may require
explicit user consent or platform-specific handling. Treat it as an emergency
fallback, not the default path.

## Payload Budget

The default push envelope budget is `3500` bytes. Applications should send
small encrypted control frames and use a higher-level fetch path for larger
content.
