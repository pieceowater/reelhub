# Reelhub

A self-hosted media stack that goes from bare Docker to a working setup with one
command. You ask for a movie or a show in a web UI, and it gets found,
downloaded, renamed, filed and made streamable without you touching anything in
between.

Six containers do the work; an Ansible playbook starts them and — the part that
is normally an hour of clicking through six admin panels — wires them to each
other over their REST APIs.

## What's in the stack

| Service | Port | What it's for |
|---|---|---|
| [Jellyseerr](https://github.com/fallenbagel/jellyseerr) | [5055](http://localhost:5055) | The front door. Search for a title, click request. |
| [Jellyfin](https://jellyfin.org/) | [8096](http://localhost:8096) | The media server you actually watch things on. |
| [Radarr](https://radarr.video/) | [7878](http://localhost:7878) | Finds, grabs and organises movies. |
| [Sonarr](https://sonarr.tv/) | [8989](http://localhost:8989) | Same, for TV — tracks seasons and new episodes. |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | [9696](http://localhost:9696) | One place to manage indexers; syncs them to Radarr and Sonarr. |
| [qBittorrent](https://www.qbittorrent.org/) | [8080](http://localhost:8080) | The torrent client that does the transfer. |

## How a request flows through it

```
  you ──▶ Jellyseerr ──▶ Radarr / Sonarr ──▶ Prowlarr ──▶ indexers
                                │                            │
                                │        ◀── torrent file ───┘
                                ▼
                          qBittorrent
                                │ downloads to data/downloads
                                ▼
                       Radarr / Sonarr import
                                │ renames + moves into data/media
                                ▼
                            Jellyfin ──▶ you watch it
```

Everything shares one directory tree (`data/`), mounted into every container at
the same path. That is what makes the hand-off free: when qBittorrent finishes,
Radarr moves the file across the same filesystem instead of copying it, and
Jellyfin sees it immediately.

## Requirements

- **Docker** with Compose v2 — [Docker Desktop](https://www.docker.com/products/docker-desktop/) on macOS/Windows, Docker Engine on Linux
- **Ansible** — `brew install ansible` (macOS) or `apt install ansible` (Debian/Ubuntu)
- ~2 GB of disk for the images, plus whatever your library needs

No Python packages, no Ansible collections, no Galaxy roles. The playbook uses
`ansible-core` and nothing else.

## Quick start

```bash
git clone https://github.com/pieceowater/reelhub.git
cd reelhub

# 1. Set your passwords (the file is gitignored; the template is not)
cp ansible/vars.yml.example ansible/vars.yml
$EDITOR ansible/vars.yml

# 2. Bring everything up and wire it together
make deploy
```

`make deploy` takes a few minutes on a first run — most of it is pulling images.
When it finishes, four public indexers (see below) are already searching and
you can request something right away in [Jellyseerr](http://localhost:5055) and
watch it land in [Jellyfin](http://localhost:8096).

Have accounts on private trackers? That's the one thing that can't be
pre-configured — they need your personal login or API key. Add them at
[Prowlarr](http://localhost:9696) → **Indexers** → **Add Indexer**; they sync
to Radarr and Sonarr on their own, same as the four already there.

## Default logins

Radarr and Sonarr are open on your LAN with no login. qBittorrent, Prowlarr and
Jellyfin all have one — usernames are plain defaults in `ansible/deploy.yml`'s
`vars:` block, not secrets — change them there if you want something else.

| Service | URL | Username | Password |
|---|---|---|---|
| qBittorrent | [localhost:8080](http://localhost:8080) | `admin` | `qbt_new_pass` in `ansible/vars.yml` |
| Prowlarr | [localhost:9696](http://localhost:9696) | `admin` | `prowlarr_admin_pass` in `ansible/vars.yml` |
| Jellyfin | [localhost:8096](http://localhost:8096) | `pcwt` | `jellyfin_admin_pass` in `ansible/vars.yml` |

Prowlarr only asks for this when reached from outside your LAN — locally it
skips straight in (`authenticationRequired: disabledForLocalAddresses`, set
because current Prowlarr refuses to run with no login at all).

The Jellyfin login also gets you into Jellyseerr and into any Jellyfin client —
Infuse, the Jellyfin apps, a browser — pointed at this server's LAN address
(`http://<this-machine's-IP>:8096`, not `localhost`, from another device).

## Requesting movies and shows

Indexers (above) are the only manual step. Once they're in, there are two ways
to actually get something onto the server — day to day you'll want the first.

### The easy way: Jellyseerr

Open [localhost:5055](http://localhost:5055), sign in with the Jellyfin admin
account (see [Default logins](#default-logins) below), search for a title, and
click **Request**. This is what to hand the rest of the household — one search
box, no other apps to learn, and requests can be approved automatically or held
for you to review (Settings → Users, or per-request in Settings → General).

### The direct way: Radarr and Sonarr

Useful for one-off searches, checking why something hasn't downloaded, or
picking a specific release yourself instead of taking whatever Jellyseerr grabs.

- **Movies** — [localhost:7878](http://localhost:7878) (Radarr) → **Add New** →
  search the title → **Add Movie**. Radarr searches your indexers immediately
  and again on its normal schedule until it finds a match.
- **TV shows** — [localhost:8989](http://localhost:8989) (Sonarr) → **Add New**
  → search the title → **Add Series**. Sonarr then also watches for new
  episodes on its own as they air.

### What happens after you add something

1. Radarr/Sonarr find a release via Prowlarr and send it to qBittorrent
2. qBittorrent downloads it into `data/downloads`
3. Once complete, Radarr/Sonarr rename and move it into `data/media` — the same
   directory tree Jellyfin's libraries point at, so this is a fast move, not a
   slow re-copy
4. Jellyfin picks it up (usually within a few minutes) and it's ready to watch,
   including in Infuse or any other Jellyfin client on your network

Nothing showing up? See [Troubleshooting](#troubleshooting) — the most common
cause by far is skipping the indexer step above.

## Everyday commands

| Command | What it does |
|---|---|
| `make deploy` | Start the stack and run the full configuration playbook |
| `make up` | Start the containers, nothing else |
| `make down` | Stop and remove the containers (your data and settings stay) |
| `make restart` | `down` then `up` |
| `make ps` | Show what is running |
| `make logs` | Tail every container's logs (`make logs S=radarr` for one) |
| `make pull` | Pull the pinned images again and recreate the containers (it does **not** upgrade anything — see [Versions](#versions)) |
| `make urls` | Print the service URLs |
| `make destroy` | Reset every service to first-boot state — removes `config/`, keeps `data/`. Asks for confirmation. |

Run `make` with no arguments for the same list.

## What the playbook sets up for you

1. Creates the `data/` and `config/` tree the containers bind-mount.
2. `docker compose up -d`.
3. **qBittorrent** — reads the one-time password the container prints on first
   boot, creates the `movies` and `tv` categories that keep the two libraries
   apart, then replaces the password with yours and sets the download directory.
4. Reads the API keys Radarr, Sonarr and Prowlarr generate on first boot.
5. **Radarr / Sonarr** — registers qBittorrent as their download client and adds
   the root folder each one imports into.
6. **Prowlarr** — registers Radarr and Sonarr as apps with full sync, then adds
   four public indexers (see [Default indexers](#default-indexers)) so both
   apps already have somewhere to search. Anything else you add propagates
   automatically the same way.
7. **Jellyfin** — runs the first-boot wizard headlessly, creates the admin user
   and adds the Movies and TV Shows libraries.
8. **Jellyseerr** — signs it in against Jellyfin, registers Radarr and Sonarr, and
   finishes its setup wizard, so opening it the first time drops you straight
   into the app instead of another setup screen.

Every step here is idempotent and everything is verified end-to-end (see
[Versions](#versions) for why that verification mattered), but steps 7–8 drive
Jellyfin and Jellyseerr's internal setup-wizard endpoints rather than a stable,
documented API, and those are more likely to shift on a future image update. If
one ever does fail, the playbook keeps going and tells you to finish that piece
by hand in the browser.

Re-running is safe: every step checks what is already configured and skips it,
rather than relying on the APIs to reject duplicates. That matters more than it
sounds — Radarr answers `400` both for "this already exists" and for "I could not
reach that download client", so a playbook that waves 400s through reports
success while configuring nothing.

## Default indexers

Four public indexers get added to Prowlarr automatically — no account needed
for any of them, and each was hand-checked to return real, well-seeded results
before being added here:

| Indexer | Good for |
|---|---|
| [YTS](https://yts.mx/) | Movies, small file sizes |
| [The Pirate Bay](https://thepiratebay.org/) | General — movies and TV |
| [LimeTorrents](https://www.limetorrents.info/) | General — TV mainly (see note below) |
| [TorrentDownload](https://www.torrentdownload.info/) | General — movies and TV |

They're deliberately conservative: a few other well-known public trackers
(1337x, EZTV, the KickassTorrents mirrors) sit behind Cloudflare and need a
[FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) proxy to return
anything at all — this stack doesn't run one, so they were left out rather than
added silently broken. Add FlareSolverr as a seventh service and they become
worth adding too.

LimeTorrents lists a Movies category but Prowlarr's own sync only ends up
wiring it to Sonarr, not Radarr — a quirk of how that indexer reports its
categories, not a misconfiguration; Radarr already has three solid sources.

Want more, or your own private trackers? Same process either way: Prowlarr →
**Indexers** → **Add Indexer** → search by name. Public ones need nothing;
private ones need the account/API key from that tracker.

## What it deliberately does not do

- **Add your private tracker accounts to Prowlarr.** By definition, only you
  have those credentials.
- **Configure hardware transcoding in Jellyfin.** Entirely dependent on your GPU
  and host OS — set it in Dashboard → Playback.

## Layout

```
reelhub/
├── docker-compose.yml      the six services
├── Makefile                every command you need day to day
├── ansible/
│   ├── deploy.yml          the playbook (heavily commented)
│   ├── vars.yml.example    template — copy to vars.yml and set the passwords
│   ├── vars.yml            your two real passwords, nothing else (gitignored)
│   ├── inventory.ini       localhost, local connection
│   └── ansible.cfg         so `ansible-playbook deploy.yml` just works
├── config/                 per-service state, created on first run (gitignored)
└── data/                   media + downloads, created on first run (gitignored)
    ├── downloads/
    └── media/{movies,tv}
```

## Versions

Every image in `docker-compose.yml` is pinned to an exact tag:

| Service | Pinned at |
|---|---|
| qBittorrent | `5.2.3` |
| Prowlarr | `2.5.2` |
| Radarr | `6.3.0` |
| Sonarr | `4.0.19` |
| Jellyfin | `10.11.11` |
| Jellyseerr | `2.7.3` |

This is deliberate, and it is the main reason the stack keeps working without
attention. With `:latest`, an unrelated `docker compose pull` can replace a
service with a new major release and break the wiring between them — which is
exactly what happened while this was being built: qBittorrent 5 renamed its
session cookie, and **Jellyfin 12 removed the `X-Emby-Authorization` header that
Jellyseerr still authenticates with**, so on `jellyfin:latest` Jellyseerr cannot
log in at all and the whole request flow is dead. Jellyfin is therefore held on
10.x until Jellyseerr supports 12.

To move a service up, change its tag and run `make pull`. Do one at a time, so
that if something breaks you know what caused it.

## Configuration

**`ansible/vars.yml`** — exactly two secrets: the qBittorrent and Jellyfin
admin passwords. Copy it from `vars.yml.example` and set both before your first
`make deploy`.

**The `vars:` block at the top of `ansible/deploy.yml`** — everything else:
ports, usernames, download categories, library paths. None of it is a secret,
so it lives in the playbook rather than in a file you have to remember exists.
Change a value there directly; a port change also needs the matching `ports:`
line in `docker-compose.yml` updated in the same commit.

**`docker-compose.yml`** — the user the containers run as and the timezone, at
the top of the file:

```yaml
PUID: ${PUID:-1000}     # `id -u` — match your host user so files aren't root-owned
PGID: ${PGID:-1000}     # `id -g`
TZ: ${TZ:-Asia/Almaty}
```

Edit the defaults there, or override them for one run from your shell
(`PUID=$(id -u) make up`). On Linux, matching your own IDs is worth doing; on
macOS, Docker Desktop handles ownership and you can leave it alone.

## Keeping your passwords out of git

`ansible/vars.yml` is gitignored — `vars.yml.example` is the one that gets
committed. If you would rather have the real file in the repo, encrypt it first:

```bash
ansible-vault encrypt ansible/vars.yml
make deploy ANSIBLE_ARGS=--ask-vault-pass
```

## Troubleshooting

**A Jellyfin or Jellyseerr task says `failed (ignored)`.** On a clean run with
the pinned image versions this shouldn't happen — every step there is
end-to-end verified, not just checked for an HTTP status. If it does, Jellyfin
or Jellyseerr shipped an update that moved one of their internal setup-wizard
endpoints (unlike Radarr/Sonarr/Prowlarr/qBittorrent, these two don't expose a
stable public API for it). Open [localhost:8096](http://localhost:8096) and
[localhost:5055](http://localhost:5055) and click through the setup once;
everything else is already configured. If you changed the Jellyfin tag to 12.x,
Jellyseerr will not be able to sign in at all — see [Versions](#versions).

**Prowlarr shows an "Authentication Required" modal you can't get past.** Means
it started before the playbook's Prowlarr step ran, or that step failed — check
`make logs S=prowlarr` and re-run `make deploy`. To set it by hand instead: pick
**Forms (Login Page)**, set **Authentication Required** to **Disabled for Local
Addresses**, and choose a username/password — this doesn't affect the
Radarr/Sonarr integration, which authenticates with an API key, not this login.

**qBittorrent returns 403 "Your IP address has been banned".** It bans a client
for an hour after a few failed logins, which is easy to trigger while you are
getting `vars.yml` right. The ban list is only in memory:
`docker compose restart qbittorrent` clears it, then `make deploy` again.

**`Could not read one or more API keys`.** One of the *arr containers did not
finish starting. Check `make logs S=radarr`, then re-run `make deploy`.

**qBittorrent login fails.** The playbook sets the password from `vars.yml` on
the first run. If you changed it there afterwards, the container still has the
old one — set it in the qBittorrent UI under Tools → Options → Web UI, or
`make down && rm -rf config/qbittorrent && make deploy` to start that service
clean.

**Nothing is ever found.** You have no indexers yet. See step 1–3 of the quick
start; this is the one manual step.

**A port is already taken.** Change it in the `vars:` block at the top of
`ansible/deploy.yml` *and* in the matching `ports:` line in
`docker-compose.yml`, then `make deploy`.

## Legal

This sets up software for managing and streaming a media library. What you point
it at is on you — use it with content you have the right to download, such as
public-domain films, Creative Commons releases, Linux ISOs, or your own ripped
discs.
