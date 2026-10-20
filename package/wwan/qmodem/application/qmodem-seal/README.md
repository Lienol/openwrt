# qmodem-seal

`qmodem-seal` encrypts collected QModem fixture archives before contributors
upload them to a public issue. It is an optional package selected by default by
QModem.

## Identity

The maintainer chooses a case-sensitive 16-64 character ASCII token using only
`A-Z`, `a-z`, `0-9`, `.`, `_`, and `-`. The token is read from the terminal
without echo and is never passed as a command-line argument.

```sh
qmodem-seal identity derive
```

The command asks for the token twice and prints a reproducible public recipient
and recipient ID. The same token always produces the same identity. The token
must never be published; releases contain only the public recipient.

Identity derivation uses Argon2id 1.3 with libsodium's moderate limits, a fixed
`QModemSealTokV1!` domain salt, and `crypto_box_seed_keypair`. Changing these
parameters would create a new token format version.

## Feedback format

An encrypted feedback file is an uncompressed outer tar:

```text
qmodem_feedback_<timestamp>.tar
  manifest.json
  payload.enc
```

- `payload.enc` is a framed libsodium secretstream using
  XChaCha20-Poly1305 and a fresh random 256-bit review key.
- `manifest.json` contains non-secret routing metadata and the review key
  wrapped for the release recipient with a libsodium sealed box. Possession of
  the manifest does not reveal the review key without the identity token.

The contributor receives the per-package review password/key after packing and
can decrypt the feedback locally. It is a generated key rather than a
human-chosen password, so it can safely carry the full encryption strength:

```sh
qmodem-seal decrypt --review-key \
  --input qmodem_feedback_<timestamp>.tar \
  --output qmodem_review.tar.gz
```

The maintainer omits `--review-key` and enters the identity token instead:

```sh
qmodem-seal decrypt \
  --input qmodem_feedback_<timestamp>.tar \
  --output qmodem_testcases.tar.gz
```

Another project maintainer can extract and send only `manifest.json` to the
identity owner. The owner does not need to download `payload.enc`; this command
recovers the package-specific review key for the other maintainer:

```sh
qmodem-seal review-key --manifest manifest.json
```

Plaintext is not released until every encrypted frame and the final stream tag
have been authenticated. Different encryptions of the same input produce
different ciphertexts.
