# mob_cellular

Cellular fallback transport plugin for the `mob` ecosystem.

`mob_cellular` provides a last-resort transport for devices that cannot reach
each other over BLE, WiFi, or mesh. The initial bridge uses small push
notification envelopes over FCM/APNs and delegates provider-specific delivery
to an injected push client.

## Carrier Decision

The primary carrier is `:push`.

Push notifications are the initial carrier because they are battery efficient,
work in the background, and are already mediated by the mobile operating
systems. SMS is recognized in the manifest as a future fallback only; the
initial bridge does not send SMS.

## Configuration

```elixir
config :mob_cellular, config: [
  carrier: :push,
  push_providers: [:fcm, :apns],
  max_payload_bytes: 3500,
  log_level: :info
]
```

Unknown keys are tolerated for forward compatibility. Unsupported carriers
raise `Mob.Cellular.CarrierRejectedError`.

## Transport Usage

`Mob.Cellular.bridge_module/0` returns `Mob.Cellular.PushBridge`, which
implements `Mob.Transport`.

```elixir
{:ok, cellular} =
  Mob.Transport.Adapter.start_link(
    transport: Mob.Cellular.bridge_module(),
    event_target: self(),
    transport_opts: [
      push_client: MyApp.PushClient,
      config: Application.get_env(:mob_cellular, :config, [])
    ]
  )

:ok = Mob.Transport.Adapter.send_frame(cellular, "peer-id", "payload")
```

The push client must implement:

```elixir
def deliver(peer_id, envelope, opts) do
  # Send `envelope` through FCM/APNs for `peer_id`.
end
```

Inbound push payloads should be delivered to the bridge process with
`Mob.Cellular.PushBridge.receive_push/2`. Decoded frames are emitted as
canonical `Mob.Transport` events.

## Limits

- Latency can be seconds or longer.
- Payloads must stay small; large frames should be handled by a higher-level
  store-and-fetch protocol.
- Payloads traverse Google or Apple push infrastructure.
- Constant polling is out of scope; this transport is push-based.
