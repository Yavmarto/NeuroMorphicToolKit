# neurohub_frontend

Flutter frontend package for the Neurohub module.

Currently owns the **Connect GitHub** screen (`GithubConnectScreen`), which runs
Neurohub's OAuth **Device Flow** through the module backend:

1. `GET /api/neurohub/oauth/config` — confirm the provider is configured.
2. `POST /api/neurohub/oauth/device/start` — start the device flow.
3. Show `user_code` and `verification_uri` (copy-to-clipboard + launchable link).
4. Poll `POST /api/neurohub/oauth/device/poll` until `success` / `expired` / `denied`.

On success the GitHub access token is persisted client-side in the platform
secure store (`GithubTokenStorage`) — see
`docs/neurohub/developer_guide.md` for the rationale.

## Layout

- `lib/src/github_device_flow_client.dart` — HTTP client + response models.
- `lib/src/github_token_storage.dart` — secure-store token persistence.
- `lib/src/github_link_launcher.dart` — opens the verification URI.
- `lib/src/github_connect_screen.dart` — the Connect GitHub screen.
- `lib/src/github_connect_theme.dart` — colors mirrored from the launcher's
  `NmtkShellTokens` (this package cannot import `neuro_toolkit` without a
  dependency cycle).

## Using it

```dart
GithubConnectScreen(
  client: GithubDeviceFlowClient(),          // resolves base URL via NmtkApiBaseUrl
  tokenStorage: const SecureGithubTokenStorage(),
  onConnected: (token) => /* hand token to the app session */,
)
```

## Testing

```bash
flutter test
```

Widget tests mock the HTTP layer with `package:http/testing.dart`'s
`MockClient` and cover: showing the code/URL, polling, the connected
transition, expiry/denial, unconfigured-provider errors, and disconnect.
