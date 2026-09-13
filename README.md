# Reelhub

A self-hosted media stack: ask for a movie or a show, and it gets found,
downloaded, and put in front of you to watch — no manual searching for files.

## Setup

Two machines are involved: the one you type these commands on (a laptop is
fine) just needs Ansible — it never runs Docker itself. The other is the
actual server that ends up running everything; it needs nothing but Ubuntu
(or any apt-based Linux), SSH, and a user with sudo.

```bash
git clone https://github.com/pieceowater/reelhub.git
cd reelhub

cp ansible/vars.yml.example ansible/vars.yml         # 1. set your password
$EDITOR ansible/vars.yml

cp ansible/inventory.ini.example ansible/inventory.ini   # 2. point at your server
$EDITOR ansible/inventory.ini

make deploy ANSIBLE_ARGS="--ask-pass --ask-become-pass"  # 3. bring everything up
```

`--ask-pass` is your SSH login password; `--ask-become-pass` is the sudo
password, needed only the first time (to install Docker) — harmless to keep
passing it after that. Using an SSH key instead of a password? Put it in
`inventory.ini` (the file has an example line) and drop both flags.

Takes a few minutes on the first run: installing Docker, then pulling images.
When it's done, everything below already works — `make urls` prints the exact
addresses for your server.

## Login

Same username and password everywhere: **`pcwt`** and whatever you set as
`master_pass` in `ansible/vars.yml`.

| | URL |
|---|---|
| Request something to watch | `http://<server>:5055` (Jellyseerr) |
| Watch it | `http://<server>:8096` (Jellyfin) |
| Add your own private trackers | `http://<server>:9696` (Prowlarr) |

Run `make urls` for the real, clickable addresses — `<server>` above is
whatever you put in `inventory.ini`.

## Requesting a movie or show

Open Jellyseerr, sign in, search for the title, click **Request**. That's it
— this is what to give everyone in the house. Usually ready to watch within a
few minutes of the download finishing.

Nine public sources are already searching, no setup needed. Want a specific
tracker you have an account on? Prowlarr → **Indexers** → **Add Indexer**.

Jellyseerr requests default to a minimum of 1080p, not the highest quality
available. This is deliberate: a 4K release of an older or less popular title
can have only a handful of seeders and take days, while a 1080p release of the
same film often has hundreds — capping it keeps things fast without much of a
visible quality difference on most screens. Want a specific movie in 4K
anyway? Add it directly in Radarr instead and pick the Ultra-HD profile there.

Jellyfin is set to prefer Russian audio and subtitles when a file actually has
them, falling back to the original with subtitles otherwise — so both options
are there whenever the download provides them (a plain single-language rip
still just plays in whatever language it was released in).

## Requesting and watching on Apple TV

[JellySee](https://apps.apple.com/us/app/jellysee/id6748783768) is a paid tvOS
app that does the whole loop from the couch: search, request, and play, all in
one place — no need to open Jellyseerr in a browser at all. (A free
alternative that covers the same ground is
[overseerrTV](https://apps.apple.com/us/app/overseerrtv/id6476953032).)

1. Install it from the App Store on the Apple TV (requires tvOS 26.0+)
2. Point it at your Jellyseerr server: `http://<server>:5055` — get the exact
   address from `make urls`
3. Sign in with the same [Login](#login) as everywhere else

From there, searching and requesting inside the app works exactly like the
[Requesting a movie or show](#requesting-a-movie-or-show) section above — it's
just Jellyseerr's own catalog, presented as a native tvOS app instead of a
web page.

Prefer a different Jellyfin client — Infuse, the Jellyfin app, a browser? Any
of them works too, pointed at `<server>:8096` with the same login; you'd just
keep using Jellyseerr's web page (or JellySee) to request things and that
client only for watching.

## Everyday commands

| | |
|---|---|
| `make deploy` | Set everything up on the server (safe to re-run any time) |
| `make up` / `make down` | Start / stop, keeping everything you've configured |
| `make logs` | See what's happening (`make logs S=radarr` for one service) |
| `make urls` | Print every service's real address |

These (except `deploy`) just SSH to the server and run `docker compose` there
— no Ansible involved, since that's simpler for something this direct. Run
`make` with no arguments to see all of them.

Something not working? Expand **Troubleshooting** below.

---

<details>
<summary><strong>Technical details</strong> — architecture, configuration, versions, troubleshooting</summary>

## What's in the stack

| Service | Port | What it's for |
|---|---|---|
| [Jellyseerr](https://github.com/fallenbagel/jellyseerr) | 5055 | The front door. Search for a title, click request. |
| [Jellyfin](https://jellyfin.org/) | 8096 | The media server you actually watch things on. |
| [Radarr](https://radarr.video/) | 7878 | Finds, grabs and organises movies. |
| [Sonarr](https://sonarr.tv/) | 8989 | Same, for TV — tracks seasons and new episodes. |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | 9696 | One place to manage indexers; syncs them to Radarr and Sonarr. |
| [qBittorrent](https://www.qbittorrent.org/) | 8080 | The torrent client that does the transfer. |

All six run on the server named in `ansible/inventory.ini` — `make urls`
turns this table into real links.

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

Everything shares one directory tree (`data/`), mounted into every container
at the same path — that's what makes the hand-off free: qBittorrent finishes,
Radarr moves the file across the same filesystem instead of copying it, and
Jellyfin sees it right away. Both directories live on the server, under this
repo's own checkout there (see [Layout](#layout)) — nothing is stored on
whatever machine you run `make deploy` from.

qBittorrent, Radarr, Sonarr and Prowlarr all use the same `pcwt` login as
Jellyfin. Each only asks for it when reached from *outside* your LAN — inside
it, they skip straight in.

### Default indexers

Nine public indexers get added to Prowlarr automatically — no account needed,
each hand-checked to return real, well-seeded results:

| Indexer | Good for |
|---|---|
| [YTS](https://yts.mx/) | Movies, small file sizes |
| [The Pirate Bay](https://thepiratebay.org/) | General — movies and TV |
| [TorrentDownload](https://www.torrentdownload.info/) | General — movies and TV |
| [Torrent Downloads](https://www.torrentdownloads.info/) | General — movies and TV (a different site from the one above, despite the name) |
| [LimeTorrents](https://www.limetorrents.info/) | General — mainly TV |
| [RuTor](https://rutor.info/) | Russian-language, dubbed/multi-audio releases |
| [NoNaMe Club](https://nnmclub.to/) | Russian-language, dubbed/multi-audio releases |
| [BigFANGroup](https://bigfangroup.org/) | Russian-language, dubbed/multi-audio releases |
| [Knaben](https://knaben.org/) | Meta-search across many trackers at once |

Left out on purpose: 1337x, EZTV, the KickassTorrents mirrors, Internet
Archive and Magnet Cat. The first three sit behind Cloudflare and need a
[FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) proxy this stack
doesn't run; the last two failed outright when tested (a DNS/SSL error and a
Cloudflare block).

Not every indexer above ends up wired to *both* Radarr and Sonarr — each app
test-searches a new indexer before accepting it and silently skips it if that
one query comes back empty, independent of whether the indexer actually
works. Harmless: Prowlarr still has all nine, so nothing is missing, just
possibly not auto-wired to one specific app. Add it there by hand (Settings →
Indexers → Add Indexer, it'll offer to import from Prowlarr) if you want it.

### How it works

`make deploy` runs `ansible/deploy.yml` from your machine against the server
named in `inventory.ini`. What it does there, in order:

0. **Bootstrap** — installs Docker and the Compose plugin if they're missing
   (the only part that needs sudo), adds your SSH user to the `docker` group,
   and checks out this repo on the server itself (default:
   `~/reelhub` — see `reelhub_dir` in `deploy.yml`'s `vars:` block).
1. Creates the `data/` and `config/` directories the containers use, inside
   that checkout.
2. Starts all six containers.
3. **qBittorrent** — sets the permanent username/password and download path,
   creates the `movies`/`tv` categories.
4. **Radarr / Sonarr** — connects qBittorrent as the download client, sets the
   library folder each one imports into, sets a Web UI login of their own.
5. **Prowlarr** — connects Radarr and Sonarr, adds the nine public indexers,
   sets a Web UI login.
6. **Jellyfin** — creates the admin account, adds the Movies and TV libraries,
   sets Russian as the preferred audio/subtitle language.
7. **Jellyseerr** — signs in against Jellyfin, connects Radarr and Sonarr on
   the HD-1080p quality profile (not the factory default "Any" — see
   [Requesting a movie or show](#requesting-a-movie-or-show) for why that
   matters), finishes its own setup so it's ready on first open.

Re-running `make deploy` is always safe: every step checks what's already
there and skips it — step 0 in particular does nothing at all once Docker is
installed and the repo is checked out, so `--ask-become-pass` stops being
necessary after the first run. Steps 6–7 drive Jellyfin/Jellyseerr's internal
setup screens rather than a documented API, so they're the ones most likely
to need a manual finish in the browser after a future image update.

Ansible modules run on the target you name in `inventory.ini`, not on the
machine you type `make deploy` on — that's *why* this works at all: every
`localhost:PORT` API call throughout `deploy.yml` correctly means the server,
because the task making that call is itself running there.

### Layout

```
reelhub/
├── docker-compose.yml       the six services
├── Makefile                 every command you need day to day
├── ansible/
│   ├── deploy.yml           the playbook — defaults, usernames and rationale live here
│   ├── vars.yml.example     template — copy to vars.yml and set the password
│   ├── vars.yml             your one real password, nothing else (gitignored)
│   ├── inventory.ini.example  template — copy to inventory.ini and name your server
│   ├── inventory.ini        your server's real address (gitignored)
│   └── ansible.cfg          so `ansible-playbook deploy.yml` just works
├── config/                  per-service state — lives on the SERVER (gitignored)
└── data/                    media + downloads — lives on the SERVER (gitignored)
    ├── downloads/
    └── media/{movies,tv}
```

This tree exists twice: once here, wherever you cloned it to run `make
deploy` from, and once more on the server itself, at `~/reelhub` by default —
Ansible's bootstrap step (see [How it works](#how-it-works)) puts it there.
`config/` and `data/` only ever populate in the *server's* copy, since that's
where the containers actually run.

### Configuration

**`ansible/vars.yml`** — one password (`master_pass`), used for qBittorrent,
Radarr, Sonarr, Prowlarr and Jellyfin alike. Copy it from `vars.yml.example`
and set it before your first `make deploy`. Want a different password for
just one of them instead? See the comments in `vars.yml.example`.

**`ansible/inventory.ini`** — your server's address and SSH login. Copy it
from `inventory.ini.example`; the file itself documents password vs. SSH-key
auth, and how to point it at `localhost` instead if you ever want to test
without a separate machine.

**The `vars:` block at the top of `ansible/deploy.yml`** — everything else:
the shared username, ports, download categories, library paths, and where the
repo gets checked out on the server (`reelhub_dir`). None of it is a secret,
so it lives in the playbook rather than a file you have to remember exists.
Changing a port also means updating the matching `ports:` line in
`docker-compose.yml`.

**`docker-compose.yml`** — the container user and timezone, near the top:

```yaml
PUID: ${PUID:-1000}     # `id -u` on the server — match it so files aren't root-owned
PGID: ${PGID:-1000}     # `id -g` on the server
TZ: ${TZ:-Asia/Almaty}
```

These are read from a `.env` file *on the server*, next to the checked-out
`docker-compose.yml` — create one there if you want something other than the
defaults; Ubuntu's first user is almost always UID/GID 1000, so this is
usually fine to leave alone.

**Keeping `vars.yml`/`inventory.ini` out of git**: both are already
gitignored — the `.example` files are what get committed. To keep the real
files in the repo instead, encrypt them:

```bash
ansible-vault encrypt ansible/vars.yml
make deploy ANSIBLE_ARGS="--ask-pass --ask-become-pass --ask-vault-pass"
```

### Versions

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
`docker compose pull` on `:latest` can silently swap in a new major release
and break how the services talk to each other — Jellyfin 12, for instance,
removed the header Jellyseerr signs in with, so Jellyseerr can't authenticate
at all on that version. Jellyfin stays on 10.x until Jellyseerr supports 12.

To move a service up, change its tag and run `make pull` — one at a time, so
you know what broke if something does.

### Troubleshooting

**`ssh: connect to host ... port 22: Connection refused` (or similar).**
Check `inventory.ini` has the right address, and that the server is actually
up and reachable — `ping <server>` from the same machine you're running
`make deploy` from.

**A bootstrap task fails asking for a password, or "Missing sudo password".**
You need `ANSIBLE_ARGS="--ask-pass --ask-become-pass"` (password auth) the
first time you deploy to a fresh server, so Ansible can log in and then sudo
to install Docker. Once Docker is installed this becomes unnecessary, but
it's harmless to keep passing it.

**Jellyseerr says "username or password incorrect."** Double-check you're
using `pcwt`, not a different username — see [Login](#login).

**A Jellyfin or Jellyseerr task says `failed (ignored)`.** Shouldn't happen on
a clean run with the pinned versions — every step there is checked against the
real app state, not just an HTTP status. If it does, that app's internal setup
screens likely shifted in an update. Open Jellyfin or Jellyseerr in a browser
(`make urls` for the addresses) and click through the setup once by hand;
everything else is already configured.

**Prowlarr shows an "Authentication Required" modal you can't get past.**
Means the playbook's Prowlarr step didn't run or failed — check
`make logs S=prowlarr` and re-run `make deploy`. To set it by hand: pick
**Forms (Login Page)**, set **Authentication Required** to **Disabled for
Local Addresses**, choose a username/password. Doesn't affect the
Radarr/Sonarr integration, which uses an API key, not this login.

**qBittorrent returns 403 "Your IP address has been banned."** It bans a
client for an hour after a few failed logins — easy to trigger while you're
getting `vars.yml` right. `make logs S=qbittorrent` to confirm, then
`ssh <server> "cd reelhub && docker compose restart qbittorrent"` clears it
(the ban list is only in memory), then `make deploy` again.

**qBittorrent login fails after you changed the password in `vars.yml`.** The
container still has the old one. Set it directly in the qBittorrent UI (Tools
→ Options → Web UI), or `make down`, then on the server
`rm -rf reelhub/config/qbittorrent`, then `make deploy` to start that service
clean.

**`Could not read one or more API keys`.** One of the *arr containers didn't
finish starting. Check `make logs S=radarr`, then re-run `make deploy`.

**Nothing is ever found.** Check [Default indexers](#default-indexers) — if
you're looking for something all nine public ones genuinely don't have, add
your own private tracker the same way.

**A port is already taken.** Change it in the `vars:` block at the top of
`ansible/deploy.yml` *and* the matching `ports:` line in `docker-compose.yml`,
then `make deploy`.

### Legal

This sets up software for managing and streaming a media library. What you
point it at is on you — use it with content you have the right to download,
such as public-domain films, Creative Commons releases, Linux ISOs, or your
own ripped discs.

</details>
