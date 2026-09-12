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
git clone https://github.com/<you>/reelhub.git
cd reelhub

# 1. Set your passwords (the file is gitignored; the template is not)
cp ansible/vars.yml.example ansible/vars.yml
$EDITOR ansible/vars.yml

# 2. Bring everything up and wire it together
make deploy
```

`make deploy` takes a few minutes on a first run — most of it is pulling images.
When it finishes it prints every URL and login.

Then do the one thing that cannot be automated:

1. Open [Prowlarr](http://localhost:9696) → **Indexers** → **Add Indexer**
2. Add the trackers you use, with your own accounts or API keys
3. They sync to Radarr and Sonarr on their own — you never add them twice

Now request something in [Jellyseerr](http://localhost:5055) and watch it land in
[Jellyfin](http://localhost:8096).

## Everyday commands

| Command | What it does |
|---|---|
| `make deploy` | Start the stack and run the full configuration playbook |
| `make up` | Start the containers, nothing else |
| `make down` | Stop and remove the containers (your data and settings stay) |
| `make restart` | `down` then `up` |
| `make ps` | Show what is running |
| `make logs` | Tail every container's logs (`make logs S=radarr` for one) |
| `make pull` | Pull newer images, then recreate the containers |
| `make urls` | Print the service URLs |
| `make destroy` | Reset every service to first-boot state — removes `config/`, keeps `data/`. Asks for confirmation. |

Run `make` with no arguments for the same list.

## What the playbook sets up for you

1. Creates the `data/` and `config/` tree the containers bind-mount.
2. `docker compose up -d`.
3. **qBittorrent** — reads the one-time password the container prints on first
   boot, replaces it with yours, sets the download directory, and creates the
   `movies` and `tv` categories that keep the two libraries apart.
4. Reads the API keys Radarr, Sonarr and Prowlarr generate on first boot.
5. **Radarr / Sonarr** — registers qBittorrent as their download client and adds
   the root folder each one imports into.
6. **Prowlarr** — registers Radarr and Sonarr as apps with full sync, so indexers
   you add later propagate automatically.
7. **Jellyfin** — runs the first-boot wizard headlessly, creates the admin user
   and adds the Movies and TV Shows libraries.
8. **Jellyseerr** — links it to Jellyfin, Radarr and Sonarr.

Steps 1–6 use documented, stable APIs. Steps 7–8 drive setup-wizard endpoints
that change between releases, so they are best-effort: if they fail the playbook
keeps going and tells you to finish those two in the browser.

Re-running is safe. Creating something that already exists returns 400/409, and
the playbook treats those as success rather than errors.

## What it deliberately does not do

- **Add indexers to Prowlarr.** These need your personal tracker accounts and API
  keys. Nobody can pre-bake that, and you would not want them to.
- **Configure hardware transcoding in Jellyfin.** Entirely dependent on your GPU
  and host OS — set it in Dashboard → Playback.

## Layout

```
reelhub/
├── docker-compose.yml      the six services
├── Makefile                every command you need day to day
├── .env.example            optional: PUID/PGID/TZ overrides
├── ansible/
│   ├── deploy.yml          the playbook (heavily commented)
│   ├── vars.yml.example    template — copy to vars.yml and edit
│   ├── vars.yml            your real settings + passwords (gitignored)
│   ├── inventory.ini       localhost, local connection
│   └── ansible.cfg         so `ansible-playbook deploy.yml` just works
├── config/                 per-service state, created on first run (gitignored)
└── data/                   media + downloads, created on first run (gitignored)
    ├── downloads/
    └── media/{movies,tv}
```

## Configuration

**`ansible/vars.yml`** — ports, credentials, library paths. Copy it from
`vars.yml.example` and change at least the two passwords before your first
`make deploy`.

**`.env`** (optional) — copy from `.env.example` to override the user the
containers run as, or the timezone:

```bash
PUID=1000        # `id -u`  — match your host user so files aren't root-owned
PGID=1000        # `id -g`
TZ=Asia/Almaty
```

The defaults are baked into `docker-compose.yml`, so this file is only needed if
you want something else. On Linux, setting `PUID`/`PGID` to your own IDs is worth
doing; on macOS, Docker Desktop handles ownership and you can ignore it.

## Keeping your passwords out of git

`ansible/vars.yml` is gitignored — `vars.yml.example` is the one that gets
committed. If you would rather have the real file in the repo, encrypt it first:

```bash
ansible-vault encrypt ansible/vars.yml
make deploy ANSIBLE_ARGS=--ask-vault-pass
```

## Troubleshooting

**A Jellyfin or Jellyseerr task says `failed (ignored)`.** Expected on some image
versions — their wizard APIs shift between releases. Open
[localhost:8096](http://localhost:8096) and [localhost:5055](http://localhost:5055)
and click through the setup once. Everything else is already configured.

**`Could not read one or more API keys`.** One of the *arr containers did not
finish starting. Check `make logs S=radarr`, then re-run `make deploy`.

**qBittorrent login fails.** The playbook sets the password from `vars.yml` on
the first run. If you changed it there afterwards, the container still has the
old one — set it in the qBittorrent UI under Tools → Options → Web UI, or
`make down && rm -rf config/qbittorrent && make deploy` to start that service
clean.

**Nothing is ever found.** You have no indexers yet. See step 1–3 of the quick
start; this is the one manual step.

**A port is already taken.** Change it in `ansible/vars.yml` *and* in the
matching `ports:` line in `docker-compose.yml`, then `make deploy`.

## Legal

This sets up software for managing and streaming a media library. What you point
it at is on you — use it with content you have the right to download, such as
public-domain films, Creative Commons releases, Linux ISOs, or your own ripped
discs.
