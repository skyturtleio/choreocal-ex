# Choreocal

A private, online-first teaching planner built with Phoenix 1.8, LiveView, Ash,
AshPostgres and AshAuthentication. Runtime: **Elixir 1.20.4-otp-29 / OTP 29.1.1**.
Dependencies are locked in `mix.lock`.

## Private teaching workspace

- Invitation-only email/password access; no public registration route or strategy.
- Encrypted, HttpOnly, SameSite=Lax session cookies (Secure in production), CSRF
  protection, stored/revocable auth tokens, and active LiveView logout notification.
- Resend password setup/recovery. Links expire after 30 minutes; successful reset
  consumes the link and revokes existing sessions. Passwords require 12–72 characters.
- Responsive calendar with real class entries, date selection, upcoming/past lists,
  and direct editing. Today and new classes default to America/New_York; each class
  appears on its own local date and displays its timezone.
- Studio and categorized exercise-library CRUD; usage history and last-taught date.
- Scheduled classes with Spotify name/link, freely named ordered sections, and ordered
  exercise snapshots. Library edits/deletion never rewrite historical class cues.
- Independent duplication preserves saved snapshots, local start time and elapsed
  duration on the chosen date, including across DST. Ambiguous/nonexistent local
  inputs are rejected visibly instead of silently shifting the appointment.
- Node-local, bounded admission control: 15 sign-ins, 3 reset emails, and 10 password
  reset submissions per minute across this single-owner instance. Limits reset on
  process restart; deploy one instance. A busy bucket intentionally rejects everyone
  temporarily rather than trusting spoofable forwarding headers.

Save each edited form explicitly; add/move/delete operations save immediately. The
browser warns before leaving unsaved forms. Classes and sections cascade-delete
their nested rows; deleting a studio or library entry only clears its optional link.
All Planning actions are actor-scoped, including supplied foreign keys.

The calendar's **Import example plans** action imports the three owner-provided
May 29 / July 11 / September 19, 2026 plans, two studios and 18 library exercises.
Names, original shorthand, playlists and New York times remain editable. No Spotify
URL or Yoga Room address is invented. A durable unique owner receipt and transaction
prevent duplicate/partial imports, even after deleting an example. Import requires
authentication and explicit confirmation; nothing is seeded or imported at deploy.

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
prove inbox delivery. Tests use disposable local users and the Swoosh test adapter;
never create fixture users or send test mail in production.

## Verification

`mix precommit` runs warning-free application compilation, formatting and tests.
Auth tests exercise anonymous HTTP/LiveView denial, invalid and valid login,
captured-cookie replay after logout, live socket revocation, registration denial,
non-enumerating reset responses, expired/reused/mismatched/short-password reset
rejection, old-session invalidation, private bootstrap, CSRF and throttling.
Planner tests cover CRUD forms, access policies, cross-owner link rejection, asymmetric
section/exercise order, independent duplication, nil/non-nil historical cues, library
deletion/history, local midnight boundaries, DST gaps/repeats and one-shot import.
Run `mix ash.codegen --check` to detect resource/snapshot drift.

The additive planner migration does not alter users or tokens. Take a fresh verified
backup before deploying. Its `down` removes planner data: after real plans exist,
roll back only the application image (the old image ignores these tables), not schema.
