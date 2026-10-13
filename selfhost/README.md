# Battleborn Reborn — self-host kit

Run your own Battleborn servers with the community Reborn mod, and let friends join through
an in-game server browser that points at *your* machine instead of the official one.

There are two downloads:

| Kit | Who it's for | What it does |
|---|---|---|
| **BattlebornReborn-player.zip** | Everyone who plays | Installs the self-host build of Reborn into Battleborn and points the server browser at the host. |
| **BattlebornReborn-host.zip** | The person running servers | Everything in the player kit, plus the server browser (game coordinator), on-demand match servers, firewall rules and a startup task. |

Every player needs Battleborn in their own Steam library. It's delisted, but the **free trial still
installs** (`steam://install/394230`) and is enough for Reborn.

---

## Players

1. Install Battleborn from Steam (free trial is fine).
2. Install official Reborn once from **https://bereborn.dev** (ReBornInstaller.exe → pick your Battleborn folder).
   This kit replaces its DLLs with the self-host build; the official install handles anything else the game needs.
3. Unzip the player kit your host sent you and double-click **Install.bat**.
   - It finds Battleborn through Steam, installs the mod files, sets the server address from `server.txt`, and puts a
     **Battleborn Reborn** shortcut on your desktop.
4. Launch the game, choose any **Public** mode (Versus, Story or Operations). That opens the server browser. Pick a match → **Join**.

To undo everything and go back to the official Reborn servers: **Uninstall.bat**.

---

## Host

### What you need
- A Windows 10/11 or Windows Server PC/VM with Battleborn + official Reborn installed.
- ~2–3 GB RAM and a CPU core or two per concurrent match (each match server is a full copy of the game).
- A stable address: a DuckDNS name, a domain, or your public IP. LAN-only play can use the LAN IP.

### Install
1. Unzip the host kit, double-click **Install.bat** (it asks for admin).
2. Enter the address players will use (e.g. `yourname.duckdns.org`).
3. The installer:
   - installs the mod and creates **Serverborn.exe** (the dedicated server is a renamed copy of the game),
   - installs the server browser to `C:\BattlebornHost` and starts it at sign-in,
   - opens Windows Firewall (TCP 5000, UDP/TCP 7777–7779 by default),
   - prints your **RCON password** (also in `C:\BattlebornHost\host-settings.json`, admins only),
   - writes a ready-to-send **BattlebornReborn-player-&lt;your address&gt;.zip** to your desktop.
4. On your router, forward **TCP 5000** and **UDP 7777–7779** to this machine.

Options: `Install-Host.ps1 -PublicHost bb.example.com -MaxMatches 4 -FirstGamePort 7777`. Re-run any time to change them.

### Starting a match (server browser)
From any player's game: Public mode → **RCON Admin** → choose map/mode, set *Required Players to Start*,
enter the RCON password → **Create Game!**. The host machine starts a match server; it shows up in everyone's
browser, and the match begins once that many players have joined. When the match ends the server exits and the slot frees up.

### Always-on servers (direct connect)
Edit `C:\BattlebornHost\fixed-servers.csv` (map names are in `maps.txt`), re-run the installer to open their ports,
then run `C:\BattlebornHost\Start-FixedServers.ps1`. Each server restarts after its match ends.
Players use **Direct Connect** with `your-address:port`. Keep these ports outside the server-browser range.

### Running it on a rack / Proxmox
This mirrors 2K's split of *matchmaking* and *game servers*, scaled to a homelab:

```
            Internet / router
   TCP 5000 │   UDP 7777-77xx
            ▼
  ┌──────────────────────────────┐
  │ Windows VM "bb-host-1"       │  ← Install.bat here
  │  server browser :5000        │
  │  Serverborn #1 :7777         │
  │  Serverborn #2 :7778  ...    │
  └──────────────────────────────┘
```

- **VM sizing**: 4 vCPU / 12 GB RAM / 60 GB disk handles about 3 matches. Use VirtIO drivers, CPU type `host`.
- **Unattended start**: the server browser starts at *sign-in* because match servers need a desktop session.
  On a headless VM, enable Windows auto-logon for the host account (Sysinternals *Autologon* stores it encrypted)
  and lock the screen rather than signing out.
- **More capacity**: today the server browser launches matches only on its own machine. To add a second game VM, run
  it with its own address and port range as a separate host for now. Splitting the browser out to a Linux container
  with launch agents on several Windows VMs is the next step if you need one shared browser across many VMs.
- **Playing from the host's own LAN**: your router has to support NAT loopback (hairpin) for LAN players to join a
  public address. If it doesn't, LAN players can use Direct Connect with the host's LAN IP and the match port.

### Logs and status
- Server browser log: `C:\BattlebornHost\coordinator.log`
- Running matches: `http://localhost:5000/api/games`
- Telemetry (tick rate, memory, players): `C:\BattlebornHost\coordinator\telemetry.db`,
  or `GET /api/telemetry` with `Authorization: Bearer <RCON password>`.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Server browser empty / "Failed to refresh server list" | Host's server browser running? `http://<host>:5000/api/games` should return `[]` or a list. Router forward TCP 5000. Player's `Binaries\Win64\reborn_server.txt` has the right address. |
| Match appears but Join times out | Router forward of the UDP game ports; Windows Firewall rules exist (`Battleborn Reborn - …`). If you used a DNS name, try `GC_PUBLIC_HOST` set to the public IP (edit `host-settings.json`, re-run the installer). |
| "Create Game!" does nothing | Wrong RCON password, or all match slots are busy (raise `-MaxMatches`). See `coordinator.log`. |
| Match server starts then vanishes | Run `Serverborn.exe` by hand from `Binaries\Win64` and read its console. Make sure official Reborn is installed and the game runs normally first. |
| Game crashes at launch after installing | Run **Uninstall.bat** to restore the official DLLs, confirm official Reborn works, then reinstall. Report the build in the Reborn Discord. |

---

## Building the kits

The kits are built from source by GitHub Actions on Windows:

1. Fork/push this branch (`nexara-selfhost`) to your GitHub account.
2. Actions → **Build self-host kit** runs on every push; download the two zips from the run's artifacts.
3. Push a tag like `kit-1` to attach them to a GitHub Release.

Or locally with Visual Studio 2022 (C++ workload) + .NET 9 SDK: `selfhost\Build-Kit.ps1` from a Developer PowerShell.

## What's different from upstream Reborn

Based on Reborn commit `5862fb3` (2025-07-31), the last point where the in-game server browser and the
coordinator API match; later upstream commits are a half-finished lobby rewrite that doesn't build.

- Game: server address comes from `reborn_server.txt` (or `REBORN_GC_ENDPOINT`) instead of being hardcoded.
- Serverborn: `-RebornPort=`, `-RebornMap=`, `-RebornPlayers=` for standalone servers.
- Coordinator: listens on all interfaces; configurable executable path, ports and public address; reserves ports
  safely; kills hung servers and frees slots from crashed ones; creates its telemetry database on first run.

## Licence

Reborn is **AGPL-3.0**. If you run a modified server that other people connect to, you must offer them the source
of your version — keeping your fork public on GitHub does that. Battleborn itself belongs to Gearbox/2K;
this kit contains no game files.
