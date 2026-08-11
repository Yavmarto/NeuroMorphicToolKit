"""Akida API-token recovery on 401.

Provisioning turns API-key auth on at the host (``NEUROCHIP_AUTH_ENABLED=true``
plus a generated token) and stores the token in ``credentialRef``. When the two
get separated — a runtime installed outside the app, a recreated settings file, a
provision whose token read-back failed — every request omits ``X-API-Key``
entirely and the host answers 401 forever, with no way out from the UI. These
tests pin the recovery: re-read the token over the already-saved SSH credentials,
retry exactly once, and otherwise fail with a message that does not tell the user
to supply a key they were never given.
"""

from __future__ import annotations

import io
import urllib.error
from typing import Any
from unittest import mock

from base import LauncherControlServiceTestBase
from nmtk.launcher_control.server import RuntimeRequestError


def _unauthorized() -> urllib.error.HTTPError:
    return urllib.error.HTTPError(
        url="http://192.168.68.53:8002/api/neurochip/akida/status",
        code=401,
        msg="Unauthorized",
        hdrs=None,  # type: ignore[arg-type]
        fp=io.BytesIO(b'{"detail":"Invalid or missing API Key"}'),
    )


class _Response(io.BytesIO):
    """Minimal stand-in for the context-manager object urlopen returns."""

    status = 200

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class TestLauncherAkidaCredentialRecovery(LauncherControlServiceTestBase):
    def _host(self, **overrides: Any) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "displayName": "Lab Akida",
            "host": "192.168.68.53",
            "username": "moosebun2",
            "authMode": "password",
            "password": "hunter2",
        }
        payload.update(overrides)
        return self.state.create_akida_host(payload)

    def test_401_recovers_the_token_over_ssh_and_retries_once(self) -> None:
        host = self._host()
        host_id = str(host["id"])
        # The stored host has no credentialRef yet, so the first attempt sends no
        # X-API-Key at all — exactly the state a user hits on a host whose
        # runtime was installed outside the app.
        self.assertEqual(host["credentialRef"], "")

        calls: list[dict[str, str]] = []

        def fake_urlopen(request: Any, *_args: Any, **_kwargs: Any) -> Any:
            calls.append(dict(request.headers))
            if len(calls) == 1:
                raise _unauthorized()
            return _Response(b'{"sdk_status":"deployable"}')

        with (
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="recovered-token"
            ) as read_token,
            mock.patch("urllib.request.urlopen", side_effect=fake_urlopen),
        ):
            result = self.state._akida_json_request(
                self.state._get_akida_host(host_id),
                "GET",
                "/api/neurochip/akida/status",
            )

        self.assertEqual(result, {"sdk_status": "deployable"})
        self.assertEqual(len(calls), 2, "expected exactly one retry")
        # urllib title-cases header names.
        self.assertNotIn("X-api-key", calls[0])
        self.assertEqual(calls[1].get("X-api-key"), "recovered-token")
        read_token.assert_called_once()

        # The recovered token is persisted, so the next request starts authorized
        # instead of paying for another 401 round trip.
        self.assertEqual(
            self.state._get_akida_host(host_id)["credentialRef"], "recovered-token"
        )

    def test_recovered_token_that_still_fails_does_not_loop(self) -> None:
        host_id = str(self._host()["id"])
        attempts = 0

        def always_unauthorized(*_args: Any, **_kwargs: Any) -> Any:
            nonlocal attempts
            attempts += 1
            raise _unauthorized()

        with (
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="stale-token"
            ),
            mock.patch("urllib.request.urlopen", side_effect=always_unauthorized),
        ):
            with self.assertRaises(RuntimeRequestError) as caught:
                self.state._akida_json_request(
                    self.state._get_akida_host(host_id),
                    "GET",
                    "/api/neurochip/akida/status",
                )

        self.assertEqual(attempts, 2, "one recovery attempt, then stop")
        self.assertEqual(caught.exception.status_code, 401)

    def test_401_without_an_ssh_login_is_a_single_actionable_failure(self) -> None:
        # No username: nothing to recover the token with. The message must point
        # at adding the SSH login rather than at an API key.
        host_id = str(self._host(username="", authMode="none", password="")["id"])
        attempts = 0

        def always_unauthorized(*_args: Any, **_kwargs: Any) -> Any:
            nonlocal attempts
            attempts += 1
            raise _unauthorized()

        with (
            mock.patch.object(self.state, "_read_remote_akida_token") as read_token,
            mock.patch("urllib.request.urlopen", side_effect=always_unauthorized),
        ):
            with self.assertRaises(RuntimeRequestError) as caught:
                self.state._akida_json_request(
                    self.state._get_akida_host(host_id),
                    "GET",
                    "/api/neurochip/akida/status",
                )

        self.assertEqual(attempts, 1)
        read_token.assert_not_called()
        self.assertIn("SSH login", str(caught.exception))

    def test_unauthorized_message_never_asks_the_user_for_a_key(self) -> None:
        host = self.state._get_akida_host(str(self._host()["id"]))
        message = self.state._akida_unauthorized_message(host, "http://host:8002")

        # The host's own wording ("Invalid or missing API Key") reads as a
        # missing user credential. It is not one, and repeating it is the whole
        # confusion this replaces.
        self.assertNotIn("Invalid or missing", message)
        self.assertIn("no key needs to be entered", message.lower())
        self.assertIn("Install", message)

    def test_a_token_read_failure_leaves_the_stored_credential_alone(self) -> None:
        host_id = str(self._host()["id"])
        self.state._update_akida_host_fields(host_id, credentialRef="existing-token")

        with (
            mock.patch.object(
                self.state,
                "_read_remote_akida_token",
                side_effect=RuntimeError("ssh: connection refused"),
            ),
        ):
            recovered = self.state._recover_akida_credential(
                self.state._get_akida_host(host_id)
            )

        self.assertEqual(recovered, "")
        self.assertEqual(
            self.state._get_akida_host(host_id)["credentialRef"], "existing-token"
        )
