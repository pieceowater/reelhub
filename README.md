# Reelhub

A self-hosted media stack that goes from bare Docker to a working setup with one
command. You ask for a movie or a show in a web UI, and it gets found,
downloaded, renamed, filed and made streamable without you touching anything in
between.

Six containers do the work; an Ansible playbook starts them and — the part
that's normally an hour of clicking through six admin panels — wires them to
each other automatically.

## What's in the stack

| Service | Port | What it's for |
|---|---|---|
| [Jellyseerr](https://github.com/fallenbagel/jellyseerr) | [5055](http://localhost:5055) | The front door. Search for a title, click request. |
| [Jellyfin](https://jellyfin.org/) | [8096](http://localhost:8096) | The media server you actually watch things on. |
| [Radarr](https://radarr.video/) | [7878](http://localhost:7878) | Finds, grabs and organises movies. |
| [Sonarr](https://sonarr.tv/) | [8989](http://localhost:8989) | Same, for TV — tracks seasons and new episodes. |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | [9696](http://localhost:9696) | One place to manage indexers; syncs them to Radarr and Sonarr. |
| [qBittorrent](https://www.qbittorrent.org/) | [8080](http://localhost:8080) | The torrent client that does the transfer. |

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
the same path — that's what makes the hand-off free: qBittorrent finishes,
Radarr moves the file across the same filesystem instead of copying it, and
Jellyfin sees it right away.

## Requirements

- **Docker** with Compose v2 — [Docker Desktop](https://www.docker.com/products/docker-desktop/) on macOS/Windows, Docker Engine on Linux
- **Ansible** — `brew install ansible` (macOS) or `apt install ansible` (Debian/Ubuntu)
- ~2 GB of disk for the images, plus whatever your library needs

## Quick start

```bash
git clone https://github.com/pieceowater/reelhub.git
cd reelhub

cp ansible/vars.yml.example ansible/vars.yml   # 1. set your three passwords
$EDITOR ansible/vars.yml

make deploy                                     # 2. bring everything up
```

Takes a few minutes on a first run — most of it is pulling images. When it's
done, four public indexers are already searching (see
[Default indexers](#default-indexers)), so you can go straight to
[Jellyseerr](http://localhost:5055) and request something.

## Logins

> **The one thing to remember:** qBittorrent and Prowlarr both use `admin`.
> Jellyfin — and Jellyseerr, which signs in *as* Jellyfin — use a different
> username. Typing `admin` there will get you "username or password incorrect."

| Service | URL | Username | Password |
|---|---|---|---|
| qBittorrent | [localhost:8080](http://localhost:8080) | `admin` | `qbt_new_pass` in `ansible/vars.yml` |
| Prowlarr | [localhost:9696](http://localhost:9696) | `admin` | `prowlarr_admin_pass` in `ansible/vars.yml` |
| **Jellyfin / Jellyseerr** | [localhost:8096](http://localhost:8096) / [localhost:5055](http://localhost:5055) | **`pcwt`** | `jellyfin_admin_pass` in `ansible/vars.yml` |

The `pcwt` / `jellyfin_admin_pass` login also works in Infuse, the Jellyfin
mobile apps, or any other Jellyfin client — point them at
`http://<this machine's LAN IP>:8096` (not `localhost`) from another device.

Radarr and Sonarr have no login at all — anyone on your LAN can open them.

Usernames are plain defaults in `ansible/deploy.yml`'s `vars:` block, not
secrets. Change them there if you'd rather everything used the same one.
Prowlarr only asks for its login when reached from *outside* your LAN — inside
it, it skips straight in.

## Requesting movies and shows

**Day to day, use [Jellyseerr](http://localhost:5055).** Sign in (see
[Logins](#logins)), search, click **Request**. This is what to hand the rest
of the household — one search box, nothing else to learn.

**For a one-off search, or to pick a specific release yourself**, go direct:

- **Movies** — [Radarr](http://localhost:7878) → **Add New** → search the title → **Add Movie**
- **TV shows** — [Sonarr](http://localhost:8989) → **Add New** → search the title → **Add Series** (it then watches for new episodes on its own)

Either way, the same thing happens next: Radarr/Sonarr grab a release through
Prowlarr, qBittorrent downloads it, and once it's done Radarr/Sonarr rename and
move it into Jellyfin's library — usually ready to watch within a few minutes.

Nothing showing up? See [Troubleshooting](#troubleshooting).

## Everyday commands

| Command | What it does |
|---|---|
| `make deploy` | Start the stack and run the full configuration playbook |
| `make up` | Start the containers, nothing else |
| `make down` | Stop and remove the containers (your data and settings stay) |
| `make restart` | `down` then `up` |
| `make ps` | Show what is running |
| `make logs` | Tail every container's logs (`make logs S=radarr` for one) |
| `make pull` | Pull the pinned images again and recreate the containers (does **not** upgrade anything — see [Versions](#versions)) |
| `make urls` | Print the service URLs |
| `make destroy` | Reset every service to first-boot state — removes `config/`, keeps `data/`. Asks for confirmation. |

Run `make` with no arguments for the same list.

## Default indexers

Four public indexers are added to Prowlarr automatically — no account needed,
and each was hand-checked to return real, well-seeded results:

| Indexer | Good for |
|---|---|
| [YTS](https://yts.mx/) | Movies, small file sizes |
| [The Pirate Bay](https://thepiratebay.org/) | General — movies and TV |
| [TorrentDownload](https://www.torrentdownload.info/) | General — movies and TV |
| [LimeTorrents](https://www.limetorrents.info/) | General — mainly TV (Prowlarr only wires it to Sonarr; a quirk of the indexer, not a bug) |

Left out on purpose: 1337x, EZTV and the KickassTorrents mirrors, which sit
behind Cloudflare and need a [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr)
proxy — this stack doesn't run one, so they'd silently return nothing instead
of actually working.

**Have accounts on private trackers?** That's the one thing that genuinely
can't be pre-configured — only you have those credentials. Add them the same
way: Prowlarr → **Indexers** → **Add Indexer** → search by name. They sync to
Radarr and Sonarr automatically, same as the four already there.

## How it works

What `make deploy` actually does, in order:

1. Creates the `data/` and `config/` directories the containers use.
2. Starts all six containers.
3. **qBittorrent** — sets your permanent password and download path, creates
   the `movies`/`tv` categories.
4. **Radarr / Sonarr** — connects qBittorrent as the download client, sets the
   library folder each one imports into.
5. **Prowlarr** — connects Radarr and Sonarr, adds the four public indexers.
6. **Jellyfin** — creates the admin account, adds the Movies and TV libraries.
7. **Jellyseerr** — signs in against Jellyfin, connects Radarr and Sonarr,
   finishes its setup so it's ready to use on first open.

Re-running `make deploy` is always safe: every step checks what's already
there and skips it, rather than assuming the app will reject a duplicate.
Steps 6–7 drive Jellyfin/Jellyseerr's internal setup screens rather than a
documented API, so they're slightly more likely to need a manual finish after
a future image update; everything else is a stable, versioned API.

## Layout

```
reelhub/
├── docker-compose.yml      the six services
├── Makefile                every command you need day to day
├── ansible/
│   ├── deploy.yml          the playbook — defaults, usernames and rationale live here
│   ├── vars.yml.example    template — copy to vars.yml and set the passwords
│   ├── vars.yml            your three real passwords, nothing else (gitignored)
│   ├── inventory.ini       localhost, local connection
│   └── ansible.cfg         so `ansible-playbook deploy.yml` just works
├── config/                 per-service state, created on first run (gitignored)
└── data/                   media + downloads, created on first run (gitignored)
    ├── downloads/
    └── media/{movies,tv}
```

## Configuration

**`ansible/vars.yml`** — the three passwords (qBittorrent, Prowlarr, Jellyfin).
Copy it from `vars.yml.example` and set them before your first `make deploy`.

**The `vars:` block at the top of `ansible/deploy.yml`** — everything else:
usernames, ports, download categories, library paths. None of it is a secret,
so it lives in the playbook rather than a file you have to remember exists.
Changing a port also means updating the matching `ports:` line in
`docker-compose.yml`.

**`docker-compose.yml`** — the container user and timezone, near the top:

```yaml
PUID: ${PUID:-1000}     # `id -u` — match your host user so files aren't root-owned
PGID: ${PGID:-1000}     # `id -g`
TZ: ${TZ:-Asia/Almaty}
```

Edit the defaults there, or override for one run (`PUID=$(id -u) make up`). On
macOS with Docker Desktop you can leave this alone.

**Keeping `vars.yml` out of git**: it's already gitignored — `vars.yml.example`
is what gets committed. To keep the real file in the repo instead, encrypt it:

```bash
ansible-vault encrypt ansible/vars.yml
make deploy ANSIBLE_ARGS=--ask-vault-pass
```

## Versions

Every image is pinned to an exact tag rather than `:latest`:

| Service | Pinned at |
|---|---|
| qBittorrent | `5.2.3` |
| Prowlarr | `2.5.2` |
| Radarr | `6.3.0` |
| Sonarr | `4.0.19` |
| Jellyfin | `10.11.11` |
| Jellyseerr | `2.7.3` |

This is why the stack keeps working without attention: an unrelated
`docker compose pull` on `:latest` can silently swap in a new major release and
break how the services talk to each other — Jellyfin 12, for instance, removed
the header Jellyseerr signs in with, so Jellyseerr can't authenticate at all on
that version. Jellyfin stays on 10.x until Jellyseerr supports 12.

To move a service up, change its tag and run `make pull` — one at a time, so
you know what broke if something does.

## Troubleshooting

**Jellyseerr says "username or password incorrect."** You're probably logging
in with `admin` — Jellyfin and Jellyseerr use `pcwt`. See [Logins](#logins).

**A Jellyfin or Jellyseerr task says `failed (ignored)`.** Shouldn't happen on
a clean run with the pinned versions — every step there is checked against the
real app state, not just an HTTP status. If it does, that app's internal setup
screens likely shifted in an update. Open [Jellyfin](http://localhost:8096) or
[Jellyseerr](http://localhost:5055) and click through the setup once by hand;
everything else is already configured.

**Prowlarr shows an "Authentication Required" modal you can't get past.**
Means the playbook's Prowlarr step didn't run or failed — check
`make logs S=prowlarr` and re-run `make deploy`. To set it by hand: pick
**Forms (Login Page)**, set **Authentication Required** to **Disabled for
Local Addresses**, choose a username/password. Doesn't affect the
Radarr/Sonarr integration, which uses an API key, not this login.

**qBittorrent returns 403 "Your IP address has been banned."** It bans a
client for an hour after a few failed logins — easy to trigger while you're
getting `vars.yml` right. `docker compose restart qbittorrent` clears it (the
ban list is only in memory), then `make deploy` again.

**qBittorrent login fails after you changed the password in `vars.yml`.** The
container still has the old one. Set it directly in the qBittorrent UI (Tools
→ Options → Web UI), or `make down && rm -rf config/qbittorrent && make deploy`
to start that service clean.

**`Could not read one or more API keys`.** One of the *arr containers didn't
finish starting. Check `make logs S=radarr`, then re-run `make deploy`.

**Nothing is ever found.** Check [Default indexers](#default-indexers) —
if you're looking for something all four public ones genuinely don't have,
add your own private tracker the same way.

**A port is already taken.** Change it in the `vars:` block at the top of
`ansible/deploy.yml` *and* the matching `ports:` line in `docker-compose.yml`,
then `make deploy`.

## Legal

This sets up software for managing and streaming a media library. What you
point it at is on you — use it with content you have the right to download,
such as public-domain films, Creative Commons releases, Linux ISOs, or your
own ripped discs.
