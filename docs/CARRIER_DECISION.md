# Carrier Decision

## Primary Carrier: Push

`mob_cellular` starts with push notifications:

- Android: Firebase Cloud Messaging.
- iOS: Apple Push Notification service.

Push is the best initial cellular carrier because it is background-friendly,
battery efficient, and works across network boundaries without keeping a
custom socket alive.

## Deferred Carrier: SMS

SMS remains a possible emergency fallback, but it is not part of the initial
bridge. It has cost, consent, payload-size, encoding, rate-limit, and delivery
semantics that should be designed separately.

## Avoided Initially: Direct Cellular Data

Direct always-on cellular data is intentionally avoided for the first version.
It requires more complex connection management and is worse for battery life
than OS-managed push delivery.
