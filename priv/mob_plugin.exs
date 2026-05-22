%{
  name: :mob_cellular,
  mob_version: "~> 0.5",
  plugin_spec_version: 1,
  description:
    "Cellular fallback transport for mob using FCM/APNs push envelopes with optional future SMS fallback.",
  carriers: [:push, :sms],
  primary_carrier: :push,
  push: %{
    envelope_version: 1,
    providers: [:fcm, :apns],
    android: %{
      provider: :fcm,
      required_config: [:firebase_project_id, :sender_id],
      manifest_permissions: [
        "android.permission.POST_NOTIFICATIONS"
      ]
    },
    ios: %{
      provider: :apns,
      required_entitlements: [
        "aps-environment"
      ],
      plist_keys: %{}
    }
  },
  sms: %{
    status: :planned,
    note: "SMS fallback is intentionally excluded from the initial bridge."
  }
}
