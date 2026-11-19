# Security policy

## Report a vulnerability

Use [private vulnerability reporting](https://github.com/phrmendes/nsm/security/advisories/new). Do not open a public issue for a security problem.

## Verify a release

Every release has a `SHA256SUMS` file and its signature `SHA256SUMS.sig`. The key is the public key in `scripts/install.sh`. `install.sh` verifies the signature with `ssh-keygen` and checks the checksum of the file.

```bash
printf 'nsm-release %s\n' "$(sed -n "s/^SIGNER='\(.*\)'/\1/p" install.sh)" > signers
ssh-keygen -Y verify -f signers -I nsm-release -n nsm -s SHA256SUMS.sig < SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

Each file also has a build attestation that ties it to its commit and workflow run:

```bash
gh attestation verify nsm-linux-x86_64 --repo phrmendes/nsm
```

## Signing key

The release key lives in the repository secret `RELEASE_SIGNING_KEY`. To rotate it, create a new key, replace the public key in `scripts/install.sh`, and publish a release. Installers of older releases keep the old key.
