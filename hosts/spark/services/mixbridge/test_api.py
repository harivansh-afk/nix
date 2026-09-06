"""Exercise the public API boundary without contacting a provider or the issuer."""

import json
import time
import unittest
from unittest.mock import patch

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from fastapi.testclient import TestClient

import auth
import main


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        public = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(cls.private_key.public_key()))
        cls.public_key = jwt.PyJWK({**public, "kid": "test", "alg": "RS256", "use": "sig"})

    def setUp(self):
        auth.traffic.clear()
        auth.active_requests = 0
        self.key_fetch = patch.object(auth.keys, "get_signing_keys", return_value=[self.public_key])
        self.key_fetch.start()
        self.addCleanup(self.key_fetch.stop)
        self.provider = patch.object(main, "downloader")
        self.downloader = self.provider.start()
        self.addCleanup(self.provider.stop)
        self.client = TestClient(main.app)
        self.addCleanup(self.client.close)

    def token(self, changes=None, headers=None, key=None):
        now = int(time.time())
        claims = {"iss": auth.ISSUER, "aud": auth.AUDIENCE, "sub": "soundcloud:123",
                  "scope": "stream", "iat": now, "exp": now + 300}
        claims.update(changes or {})
        return jwt.encode(claims, key or self.private_key, algorithm="RS256",
                          headers={"kid": "test", "typ": "at+jwt", **(headers or {})})

    def authorized(self, **claims):
        return {"Authorization": "Bearer " + self.token(claims)}

    def test_every_work_route_requires_authentication(self):
        for path in ("/stream", "/download", "/spotify/stream", "/spotify/download"):
            with self.subTest(path=path):
                response = self.client.post(path, json={"url": "https://soundcloud.com/a/b"})
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.headers["www-authenticate"], "Bearer")
        self.assertEqual(self.client.get("/spotify/search?q=test").status_code, 401)
        self.downloader.assert_not_called()
        self.assertEqual(self.client.get("/health").status_code, 200)
        for path in ("/docs", "/redoc", "/openapi.json"):
            self.assertEqual(self.client.get(path).status_code, 404)

    def test_invalid_tokens_are_rejected_before_extraction(self):
        now = int(time.time())
        bad_claims = [
            {"iss": "https://attacker.invalid"}, {"aud": "another-api"},
            {"aud": [auth.AUDIENCE]}, {"scope": "admin"}, {"sub": "123"},
            {"sub": "spotify:"}, {"sub": 123}, {"exp": now - 30},
            {"iat": now + 60, "exp": now + 300}, {"exp": now + 301},
            {"iat": str(now)}, {"exp": str(now + 300)}, {"scope": None},
        ]
        tokens = [self.token(claims) for claims in bad_claims]
        tokens += [self.token(headers={"kid": "unknown"}),
                   self.token(headers={"typ": "JWT"}), "spotify:123", "not-a-jwt",
                   jwt.encode({"sub": "soundcloud:123"}, "x" * 32, algorithm="HS256"),
                   self.token(key=rsa.generate_private_key(public_exponent=65537, key_size=2048))]
        for token in tokens:
            with self.subTest(token=token[:20]):
                response = self.client.post("/stream", json={"url": "https://soundcloud.com/a/b"},
                                            headers={"Authorization": "Bearer " + token})
                self.assertEqual(response.status_code, 401)
        self.downloader.assert_not_called()
        self.assertEqual(auth.active_requests, 0)

    def test_missing_claim_and_unavailable_issuer_fail_closed(self):
        claims = jwt.decode(self.token(), options={"verify_signature": False})
        for claim in ("iss", "aud", "sub", "iat", "exp", "scope"):
            incomplete = {k: v for k, v in claims.items() if k != claim}
            token = jwt.encode(incomplete, self.private_key, algorithm="RS256",
                               headers={"kid": "test", "typ": "at+jwt"})
            with self.assertRaises(HTTPException) as error:
                auth.verify_token("Bearer " + token)
            self.assertEqual(error.exception.status_code, 401)
        with patch.object(auth.keys, "get_signing_keys", side_effect=jwt.PyJWKClientConnectionError()):
            response = self.client.post("/stream", json={"url": "https://soundcloud.com/a/b"},
                                        headers=self.authorized())
            self.assertEqual(response.status_code, 503)
        self.downloader.assert_not_called()

    def test_authenticated_ssrf_and_playlist_inputs_never_reach_downloader(self):
        invalid = ["http://127.0.0.1:19400/soundcloud.com", "https://evil.test/soundcloud.com/a/b",
                   "https://soundcloud.com.evil.test/a/b", "https://soundcloud.com@127.0.0.1/a/b",
                   "https://soundcloud.com:19400/a/b", "http://soundcloud.com/a/b",
                   "https://soundcloud.com/a/sets/playlist", "https://soundcloud.com/a/sets",
                   "https://soundcloud.com/a", "https://soundcloud.com/a/%2e%2e", "file:///soundcloud.com"]
        for path in ("/stream", "/download"):
            for url in invalid:
                with self.subTest(path=path, url=url):
                    response = self.client.post(path, json={"url": url}, headers=self.authorized())
                    self.assertEqual(response.status_code, 400)
        self.downloader.assert_not_called()
        self.assertEqual(auth.active_requests, 0)

    def test_valid_track_forces_soundcloud_extractor_and_strips_query(self):
        extractor = self.downloader.return_value.__enter__.return_value
        extractor.extract_info.return_value = {"title": "Example", "duration": 10, "formats": [
            {"url": "https://media.example/audio.mp3", "protocol": "https", "acodec": "mp3", "abr": 128}
        ]}
        response = self.client.post("/stream", headers=self.authorized(), json={
            "url": "https://www.soundcloud.com/artist/track/?next=http://127.0.0.1#fragment"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["stream_url"], "https://media.example/audio.mp3")
        extractor.extract_info.assert_called_once_with(
            "https://soundcloud.com/artist/track", download=False, ie_key="Soundcloud")
        self.assertEqual(auth.active_requests, 0)

    def test_spotify_validation_precedes_provider_requests(self):
        with patch.object(main, "get_spotify_track") as track, patch.object(main, "get_spotify_token") as token:
            for path in ("/spotify/stream", "/spotify/download"):
                response = self.client.post(path, json={"url": "https://evil.test/track/" + "a" * 22},
                                            headers=self.authorized(sub="spotify:123"))
                self.assertEqual(response.status_code, 400)
            for query in ("q=&limit=10", "q=x&limit=0", "q=x&limit=51", "q=" + "x" * 201):
                self.assertEqual(self.client.get("/spotify/search?" + query,
                                                  headers=self.authorized()).status_code, 400)
            track.assert_not_called()
            token.assert_not_called()
        for url in ("spotify:track:" + "a" * 22, "https://open.spotify.com/track/" + "a" * 22 + "?si=x"):
            self.assertEqual(main.parse_spotify_url(url), "a" * 22)

    def test_bearer_cors_and_untrusted_origins(self):
        headers = {"Origin": "https://mixbridge.app", "Access-Control-Request-Method": "POST",
                   "Access-Control-Request-Headers": "authorization,content-type"}
        response = self.client.options("/stream", headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["access-control-allow-origin"], "https://mixbridge.app")
        self.assertEqual(self.client.options("/stream", headers={**headers, "Origin": "https://evil.test"}).status_code, 400)
        self.assertEqual(self.client.post("/stream", json={"url": "x"},
                                          headers={"Origin": "https://mixbridge.app"}).headers[
                                              "access-control-allow-origin"], "https://mixbridge.app")

    def test_user_and_global_concurrency_limits_release_after_failure(self):
        opened = []
        try:
            for subject in ("soundcloud:1", "soundcloud:1", "spotify:1", "spotify:2"):
                request = auth.require_user("Bearer " + self.token({"sub": subject}))
                self.assertEqual(next(request), subject)
                opened.append(request)
            for subject in ("soundcloud:1", "spotify:3"):
                with self.assertRaises(HTTPException) as error:
                    next(auth.require_user("Bearer " + self.token({"sub": subject})))
                self.assertEqual(error.exception.status_code, 429)
            with self.assertRaises(RuntimeError):
                opened.pop().throw(RuntimeError("provider failed"))
            retry = auth.require_user("Bearer " + self.token({"sub": "spotify:3"}))
            self.assertEqual(next(retry), "spotify:3")
            opened.append(retry)
        finally:
            for request in opened:
                request.close()
        self.assertEqual(auth.active_requests, 0)
        self.assertTrue(all(bucket["active"] == 0 for bucket in auth.traffic.values()))

    def test_per_user_rate_limit_and_window_reset(self):
        token = "Bearer " + self.token()
        with patch.object(auth.time, "monotonic", return_value=100):
            for _ in range(60):
                request = auth.require_user(token)
                next(request)
                request.close()
            with self.assertRaises(HTTPException) as error:
                next(auth.require_user(token))
            self.assertEqual(error.exception.status_code, 429)
            other = auth.require_user("Bearer " + self.token({"sub": "spotify:123"}))
            next(other)
            other.close()
        with patch.object(auth.time, "monotonic", return_value=160):
            request = auth.require_user(token)
            next(request)
            request.close()

    def test_audio_size_limit_and_downloader_options(self):
        main.bound_download({"downloaded_bytes": None})
        with self.assertRaises(main.yt_dlp.DownloadError):
            main.bound_download({"downloaded_bytes": main.MAX_AUDIO_BYTES + 1})
        # Exercise the real factory rather than the provider stub used above.
        with patch.object(main.yt_dlp, "YoutubeDL") as ydl:
            self.provider.stop()
            main.downloader({"quiet": True})
            opts = ydl.call_args.args[0]
            self.assertTrue(opts["noplaylist"])
            self.assertEqual(opts["max_filesize"], main.MAX_AUDIO_BYTES)
            self.assertEqual(opts["socket_timeout"], 15)


if __name__ == "__main__":
    unittest.main()
