# Running the patched KWin and Pager from the home directory

The scripts build the patched pieces in a container and run them in a real Plasma session
without installing anything into `/usr`. That suits an immutable, rpm-based host.

They assume:

- the checkout is at `~/kde`;
- a Fedora distrobox named `kde-dev` holds the KDE build dependencies, with the same
  versions of the KDE, Qt, Wayland and PipeWire packages as the host (`pin-list.txt`);
- `src/` holds checkouts of the four KDE repositories with the patches applied.

## Working copy

Git tracks the published files. A working copy also holds these, all ignored:

- `src/`: the KDE checkouts. `make-live.sh` regenerates `patches/` from them.
- `build-live/`, `sdk/`, `ccache/`: build trees, the patched protocols, the compiler cache.
- `live-N/` and the symlink `live`: installed builds, and the one the session uses.
- `nested-home-host/`: the settings of the nested test session.

## Session

`go-live.sh` installs two systemd user drop-ins named `50-pager-thumbnails.conf`, one for
`plasma-kwin_wayland.service` and one for `plasma-plasmashell.service`. At login they run
`session/kwin-launch.sh` and `session/plasmashell-launch.sh`.

- KWin runs from `live/`.
- plasmashell is the system binary. The launcher adds `live/plasma-overlay/` to its
  `LD_LIBRARY_PATH` and `QT_PLUGIN_PATH`. The overlay holds the patched `libtaskmanager`
  and the Pager applet. Apps started from the panel inherit both paths.
- The patched KWin runs without realtime scheduling. That needs a file capability, which
  needs root.

`session/session.log` records which KWin ran and why.

## Fallback to the system KWin

`kwin-launch.sh` starts the system KWin when one of these holds:

- An update changed a package listed in `session/common.sh`. The launcher compares the
  installed versions with `live/host-versions.stamp`. Rebuild to get thumbnails back.
- The patched binaries fail the load check that runs before each start: a missing library
  or symbol.
- The patched KWin exited by itself within 5 minutes of starting. KWin's wrapper gives up
  on a crash-looping KWin with exit status 0, so the launcher goes by the time.
- The previous session ended within those 5 minutes without a stop from systemd, for
  example a hang ended with the power button.
- `~/kde/DISABLE` exists, or `~/kde` is gone.

The second, third and fourth cases create `session/FAILED`. Delete it to retry. Logging
out or rebooting early sends SIGTERM, which the launcher counts as a normal stop.

If the patched KWin fails after it registered its D-Bus name, systemd may end that login.
The next login uses the system KWin.

`plasmashell-launch.sh` drops the overlay when the overlay fails its load check, or when
plasmashell started three times within 90 seconds with it. The second case creates
`session/SHELL_FAILED`. Delete it to retry.

`tests/launcher-test.sh` runs these cases against fake binaries in a throwaway directory.
Run it after editing anything in `session/`.

## Builds

`live` is a symlink to the build in use. Install into a new directory each time; the
session maps files from the build it runs.

    ~/kde/make-live.sh N                 # builds ~/kde/live-N and checks that it loads
    PT_LIVE_DIR=~/kde/live-N ~/kde/tests/wrapper-test.sh
    ~/kde/tests/overview-test.sh live-N  # nested two-screen session; tests/nested-stop.sh ends it
    echo live-N > ~/kde/live-next        # the launcher switches the symlink at the next login

The launcher ignores a queued build that lacks binaries, the stamp or the overlay.
Switching builds clears `FAILED` and `SHELL_FAILED`. To go back to an older build, point
the symlink at it from a TTY (`ln -sfn live-M ~/kde/live`) and delete `session/FAILED` if
it exists.

`make-live.sh` does this:

1. Stops if the container holds another version than the host of any package in the stamp.
2. Builds in `build-live/` with the install prefix `~/kde/live` compiled in.
3. Takes the patched protocols from `~/kde/sdk`.
4. Installs KWin into `live-N`.
5. Copies `libtaskmanager.so.6*` and the Pager applet into the overlay and strips their rpath.
6. Writes the stamp and runs the load check.

`go-live.sh` refuses a build stamped for other package versions.

## Testing

Test an installed `live-N`. A KWin started from `build-live/` with `PT_KWIN_BUILD` runs,
but its streams fail with "no more input formats" and thumbnails stay empty.

`run-nested-host.sh` runs a build as a window on the host: `PT_LIVE_DIR=~/kde/live-N`.

The nested KWin and plasmashell log to the journal. `tests/nested-streams.sh` lists the
nested KWin's streams. A plain `pw-dump` also lists the real session's streams, because
both sessions share one PipeWire daemon.

## After a system update

The log says "system packages changed" and the thumbnails are gone.

    distrobox enter kde-dev -- sudo dnf upgrade -y
    ~/kde/make-live.sh N
    echo live-N > ~/kde/live-next

If the host is behind Fedora, pin the container to the host's versions first. `pin-list.txt`
shows the package set; Fedora's `updates-archive` repository has the older builds.

Plasma 6.8 changes the code under the patches. Port them before rebuilding.

## Roll back

    ~/kde/rollback.sh

Then log out and in. From a broken or black session: Ctrl+Alt+F3, log in, run
`~/kde/rollback.sh`, then `sudo reboot`. `--restore-config` also puts back the Plasma and
KWin config saved in `config-backup-*-prelive/`.

## Remove everything

    ~/kde/rollback.sh        # then log out and in
    distrobox rm kde-dev
    rm -rf ~/kde
