# DayZDockerServer

A Linux [DayZ](https://dayz.com) server in a [Docker](https://docs.docker.com/) container. The main script's functionality is derived from [this project](https://github.com/thelastnoc/dayz-sa_linuxserver). That functionality is described [here](https://steamcommunity.com/sharedfiles/filedetails/?id=1517338673). The goal is to reproduce some of that functionality but also add more features. 

The main goal is to provide a turnkey DayZ server with mod support that can be spun up with as little as a machine running Linux with Docker and Docker Compose installed. 

This project started when the Linux DayZ server was released for DayZ experimental version 1.14 on 09/02/2021. As of 02/20/2024, there is now an official Linux DayZ server, but...

## Caveats

* Some mods are known to crash the server on startup:
  * [DayZ Expansion AI](https://steamcommunity.com/sharedfiles/filedetails/?id=2792982069)
  * [Red Falcon Flight System Heliz](https://steamcommunity.com/workshop/filedetails/?id=2692979668) - Bug report [here](https://feedback.bistudio.com/T176564)
* Some mods work, but have bugs:
  * [DayZ Expansion Groups](https://steamcommunity.com/sharedfiles/filedetails/?id=2792983364)
    * The save file becomes corrupted and when the server restarts so the changes do not persist.
* There are other bugs:
  * [Server doesn't stop with SIGTERM](https://feedback.bistudio.com/T170721)
* After deleting the `serverfiles` docker volume, permissions are incorrect when restarting the stack, which causes file permissions errors. To fix:
```shell
docker compose run -u0 --rm web chown user:user /serverfiles -R
```
Unfortunately, this cannot be easily mitigated within the code, so it remains a manual process.

This project is a work in progress: See the [roadmap](ROADMAP.md).

## Configure and Build

Ensure [Docker](https://docs.docker.com/engine/install/) and [Docker compose](https://docs.docker.com/compose/install/) are properly installed. This means setting it up so it runs as your user. Make sure you're running these commands as your user, in your home directory.

Clone the repo, and change into the newly created directory:

```shell
git clone https://ceregatti.org/git/daniel/dayzdockerserver.git
cd dayzdockerserver
```

Create a `.env` file that contains your user id. Usually the `${UID}` shell variable has this:

```shell
echo "export USER_ID=${UID}" | tee .env
```

Build the Docker images:

```shell
docker compose build
```

### Steam Integration

[SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) is used to manage Steam downloads. A vanilla DayZ server can be installed with the `anonymous` Steam user, but most mods cannot. If the goal is to add mods, a real Steam login must be used. Login:

```shell
docker compose run --rm web dz login
```

Follow the prompts. Hit enter to accept the default, which is to use the `anonymous` user, otherwise use your real username and keep following the prompts to add your password. If you have Steam Guard (which you _really_ should have), it will wait for the request to be approved on your phone. The process will wait until it's approved.

The credentials will be managed by [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD). This will store a session token in the `homedir` docker volume. All subsequent SteamCMD commands will use this. so this process does not need to be repeated unless the session expires or the docker volume is deleted.

To manage the login credentials, simply run the above command again. See [Manage](#manage). 

## Install

The base server files must be installed before the server can be run:
```shell
docker compose run --rm web dz install
```

This will download about 3 Gigabytes of files.

## Run

Copy `files/serverDZ.cfg.example` to `serverDZ.cfg` in the `files` directory:
```shell
cp files/serverDZ.cfg.example file/serverDZ.cfg
```

This file will be used by the server within the container. Set the values of any variables there. See the [documentation](https://forums.dayz.com/topic/239635-dayz-server-files-documentation/) if you want, but most of the default values are fine. The Chernarus map is set by default in this file. Edit the file, and at the very least change the server name:

```
hostname = "Something other than Server Name";   // Server name
```

Install the server config file:

```shell
docker compose run --rm server dz config
```

The maintenance of the config file is a work in progress. The goal is to create a facility for merging changes into the config file and maintain a paper trail of changes. For now, just remember that the working config file is the one that was copied into the root of the project, and that changes to it must be copied into the container using the command above.

This only has to be done initially or when changes are made to `serverDZ.cfg`.

## Up
Launch the stack into the background:
```shell
docker compose up -d
```

There will be nothing in mpmissions when the server container starts for the first time. A pristine copy of `dayzOffline.chernarusplus` will be copied from the `mpmission` volume to the server container. This will be the default map. To install other maps, see [Maps](#maps).

To see the server log:

```shell
docker compose logs -f server
```
## Stopping the server

To stop the DayZ server:
```shell
docker compose exec server dz stop
```

If it exits cleanly, the container will also stop. Otherwise a crash is presumed and the server will restart. Ideally, the server would always exit cleanly, but... it's DayZ.

To stop the containers:
```shell
docker compose stop
```

To bring the entire stack down:
```shell
docker compose down
```

Since all files are maintained within docker volumes, all changes persist when bringing the stack down.

## Manage

### Maps

Installing another map requires installing its mod and mpmissions files. Some maps maintain github repositories or public web sites for their mpmissions, while others do not. This project aims to support DayZ maps whose mpmissions are easily accessible "Out of the box" by maintaining configuration files for them.

### RCON

A terminal-based RCON client is included: https://github.com/indepth666/py3rcon.
The dz script manages what's necessary to configure and run it:

The following command presumes the server has been brought [up](#up) (otherwise RCON can't connect to anything):

```shell
docker compose exec server dz rcon
```

To reset the RCON password in the Battle Eye configuration file, simply delete it, and a random one will be generated on the next server startup:

```shell
docker compose run --rm server rm serverfiles/battleye/baserver_x64_active*
```

Don't expect much from this RCON at this time.

### Update the DayZ server files

It's probably not a good idea to update the server files while a server is running. Bring everything down first:

```shell
docker compose down
```

Then run the command:

```shell
docker compose run --rm web dz update
```

This will update the server base files as well as all installed mods.

Don't forget to [bring it back up](#up).

### Stop the DayZ server

To stop the server:
```shell
docker compose exec server dz stop
```

The above sends the SIGINT signal to the server process. The server sometimes fails to stop with this signal. It may be necessary to force stop it with the SIGKILL:

```shell
docker compose exec server dz force
```

When the server exits cleanly, i.e. exit code 0, the container also stops. Otherwise, a crash is presumed, and the server will be automatically restarted.

To bring the entire stack down:
```shell
docker compose down
```

### Workshop - Add / List / Remove / Update mods

Interactive interface for managing mods. These commands are run with the stack being [up](#up).

```
# Adding and removing of mods is done in the web container. These commands only download, list, update, or remove mods to/from volumes that are shared by the web and server containers.
docker compose exec web dz (a)dd id | (l)ist | (m)odupdate | (r)emove id
# Once added to the web container, activate any of the installed mods in the running server. Activated mods are also deactivated here.
docker compose exec server dz (a)ctivate id [ id2 [ id3 ]] | (d)eactivate id [ id2 [ id3 ]] | (l)ist | (s)tatus
```

Look for mods in the [DayZ Workshop](https://steamcommunity.com/app/221100/workshop/). Browse to one. In its URL will be an `id` parameter. Here is the URL to Community Framework, a mod that is a dependency of many other mods (but by itself really doesn't do anything): https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036. To add it:

```shell
docker compose exec web dz add 1559212036
```

Then activate it in the server container:
```shell
docker compose exec server dz activate 1559212036
```

Activating (or deactivating) mods will add (or remove) their names from the `-mod=` parameter in the server command line.

To avoid re-downloading large mods, the `activate` and `deactivate` server container commands will simply disable the mod but keep its files. Note that mod updates will also update deactivated 
mods.

The above is a bad example, as Community Framework doesn't really do anything by itself, but is a dependency of pretty much every admin mod. Add [VPPAdminTools](https://steamcommunity.com/sharedfiles/filedetails/?id=1828439124) too:

```shell
docker compose exec web dz add 1828439124
docker compose exec shell dz activate 1828439124
```

Read the instructions on the page of the URL above to add yourself as an admin to your server.

### Looking under the hood

All the server files persist in a docker volume that represents the container's unprivileged user's home directory. Open a bash shell in the running container:

```
docker compose exec web bash
```

Or open a shell into a new container if the docker stack is not [up](#up):
```
docker compose run --rm web bash
```

All the files used by the server are in a docker volume. Any change made will be reflected upon the next container startup.

Use this shell cautiously.

# Development mode

Add the following to the `.env` file:

```shell
export DEVELOPMENT=1
```

Bring the stack down then back up. Now, instead of the server starting when the server container comes up it will simply block, keeping both the web and server containers up and accessible.

This allows access to the server container using exec. You can then start and stop the server manually, using `dz`:

```shell
# Go into the server container
docker compose exec shell bash
# See what the server status is
dz s
# Start it
dz start
```

To stop the server, hit control c.

Caveat: Some times the server doesn't stop with control c. If that's the case, control z, exit, then `dz f`. YMMV.

## TODO

* Create web management tool:
  * It shells out to `dz` (for now) for all the heavy lifting. 
* Create some way to send messages to players on the server using RCON.
* Implement multiple ids for mod commands. (In progress)
* Fix the permissions bug listed in [caveats](#caveats).
