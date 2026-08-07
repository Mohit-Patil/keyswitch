# Security Policy

## Supported versions

KeySwitch is currently pre-1.0. Security fixes are applied to the latest code
on the `main` branch and to the newest release when practical. Older builds are
not maintained.

## Reporting a vulnerability

Please use a
[private GitHub security advisory](https://github.com/Mohit-Patil/keyswitch/security/advisories/new).
Do not disclose a suspected vulnerability in a public issue, Discussion, pull
request, screenshot, or log.

Include, when possible:

- the affected commit or version;
- macOS and Codex desktop versions;
- a concise impact assessment;
- reliable reproduction steps or a minimal proof of concept;
- whether user interaction or special permissions are required; and
- a suggested mitigation, if known.

You should receive an acknowledgement within 72 hours and a status update
within seven days. These are best-effort targets for a volunteer-maintained
project. Please allow time for a fix and coordinated disclosure before
publishing details.

## Security-sensitive behavior

KeySwitch requests Input Monitoring and Accessibility permission to implement
global keyboard control. It can also restart Codex with a local Chromium
debugging port and evaluate code inside the renderer to use existing Micro
contracts. Reports involving permission misuse, event interception, renderer
evaluation, local-port exposure, unintended app control, or persistence are
especially important.

KeySwitch connects to `127.0.0.1` by default. Renderer discovery accepts only
numeric loopback WebSocket endpoints on the configured port and rejects
redirects, credentials, query strings, fragments, malformed page paths, and
discovery responses larger than 1 MiB. These checks do not authenticate a
different local process that binds the configured port first.

Do not expose the debugging port to other devices or untrusted local users.
Treat any renderer endpoint as privileged access to the running Codex session.

## Out of scope

- Compatibility breakage caused by an ordinary Codex UI update, without a
  security impact.
- Reports that require intentionally exposing the debugging port to an
  untrusted network.
- Social engineering that does not involve a KeySwitch vulnerability.

Good-faith research that follows this policy is welcome. Do not access other
people's data, degrade systems, or retain private information.
