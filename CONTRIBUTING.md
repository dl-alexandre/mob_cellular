# Contributing

## Local Checks

Run the standard checks before opening a PR:

```sh
mix deps.get
mix format --check-formatted
mix test
mix credo --strict
```

## Additional Carriers

New carriers should be implemented as separate bridge modules with their own
configuration and tests. Keep provider credentials outside bridge state and
prefer injected clients or native platform handoff modules.
