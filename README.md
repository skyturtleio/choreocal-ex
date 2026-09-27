# Choreocal

A private, online-first teaching planner built with Phoenix 1.8, LiveView, Ash,
AshPostgres and AshAuthentication. Runtime: **Elixir 1.20.4-otp-29 / OTP 29.1.1**.
Dependencies are locked in `mix.lock`.

## Delivered foundation

- Invitation-only email/password access; no public registration route or strategy.
- Encrypted, HttpOnly, SameSite=Lax session cookies (Secure in production), CSRF
  protection, stored/revocable auth tokens, and active LiveView logout notification.
- Resend password setup/recovery. Links expire after 30 minutes; successful reset
  consumes the link and revokes existing sessions. Passwords require 12–72 characters.
- Responsive authenticated calendar with month navigation, Today, date selection,
  and truthful empty states. Calendar dates use America/Chicago, including DST.
- Node-local, bounded admission control: 15 sign-ins, 3 reset emails, and 10 password
  reset submissions per minute across this single-owner instance. Limits reset on
  process restart; deploy one instance. A busy bucket intentionally rejects everyone
  temporarily rather than trusting spoofable forwarding headers.

Class/studio CRUD, ordered sections, reusable exercise library, duplication, and
usage history are **not implemented yet**. The `Planning` domain is established;
future `ClassExercise` records must retain historical name/cue snapshots independently
of optional library links. No demo classes or public credentials are seeded.

## Orb development

```sh
.agents/setup
amp orb services ensure
mix precommit
```

Setup installs checksum-pinned exact runtimes, dependencies, PostgreSQL 15 and asset
tools. The tested Ubuntu 22.04 Hex OTP binary runs on Debian 12 with its SSL/ncurses
libraries. Setup is idempotent and provisions only disposable local databases using
Unix-socket peer authentication. It does not create an application user.

`services ensure` starts supervised PostgreSQL and Phoenix and prints a shareable
portal URL. Development mail uses Swoosh.Local; tests use Swoosh.Test. There is no
public development mailbox route. Do not inject production database credentials into
local tests or expose a development server as a production deployment.

## Production release contract

The Docker build uses the exact digest-pinned runtime and creates `/app/bin/choreocal`.
The nonroot server entrypoint runs `Choreocal.Release.migrate/0` before starting HTTP,
and exits on migration failure. `GET /health` returns `{"status":"ok"}` without auth or
database writes; it is liveness, not a full database readiness check.

Required runtime variables (never build arguments or committed values):

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Private PostgreSQL connection; database role must own its schema and be able to install trusted `citext` |
| `SECRET_KEY_BASE` | Stable random Phoenix secret, at least 64 bytes |
| `TOKEN_SIGNING_SECRET` | Independent stable random AshAuthentication secret |
| `PHX_HOST` | Public hostname, e.g. `choreocal-ex.skyturtle.io` |
| `RESEND_API_KEY` | Resend key authorized for the sender domain |
| `MAIL_FROM` | Email address on the verified Resend domain |
| `PHX_SERVER` | `true` for HTTP serving |
| `PORT` | `4000` by default |

TLS terminates at the trusted reverse proxy. Production rewrites forwarded HTTPS,
sets HSTS and restricts LiveView origins to `https://PHX_HOST`. Do not expose the
container port directly to untrusted clients. Keep reverse-proxy access logs disabled
for this app so password-reset URL tokens cannot be retained. Application parameter
filters redact email/password/token values and suppress reset-path request logs.

## Private first-owner setup

No recipient is guessed and no initial password is printed or stored in plaintext.
After an explicit recipient is available, open the running application container's
private terminal and run:

```sh
printf 'Owner email: '
read -r OWNER_EMAIL
export OWNER_EMAIL
/app/bin/choreocal eval 'case Choreocal.Release.provision_owner(System.fetch_env!("OWNER_EMAIL")) do
  :ok -> IO.puts("Password setup email accepted by the mail provider.")
  {:error, _} -> IO.puts(:stderr, "Provisioning or delivery failed; inspect configuration and retry the same recipient."); System.halt(1)
end'
unset OWNER_EMAIL
```

The task does not start another HTTP listener. A database advisory lock serializes
provisioning; once one owner exists, a different recipient is refused. The account
starts with a cryptographically random, unknown password. The recipient sets their
own password using the emailed link. Re-running with the same email resends setup
instructions, which permits recovery from mail-provider failure without creating a
second account. `OWNER_EMAIL` is a one-command input, not a required boot variable.

Never send an owner password or reset URL through chat. Provider acceptance does not
prove inbox delivery. No real email has been sent during implementation because an
authorized recipient has not been supplied.

## Verification

`mix precommit` runs warning-free application compilation, formatting and tests.
Auth tests exercise anonymous HTTP/LiveView denial, invalid and valid login,
captured-cookie replay after logout, live socket revocation, registration denial,
non-enumerating reset responses, expired/reused/mismatched/short-password reset
rejection, old-session invalidation, private bootstrap, CSRF and throttling.
Calendar tests cover navigation and Chicago day boundaries in winter and summer.
