#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/freebsd-portupdater @ 95c3d8a
# │ path     : vm.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.4 subcommand dispatch · environment-variable configuration surface
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# vm.sh — manage a local FreeBSD VM on macOS for port work.
#
# Uses QEMU with Hypervisor.framework acceleration and the official FreeBSD
# VM images, so there is no installer step: `setup` downloads the image,
# boots it, configures root ssh over the serial console (official images
# allow root console login with an empty password — no cloud-init needed),
# and provisions poudriere + a ports tree in one go.
#
# Usage:
#   ./vm.sh setup               download image, first boot, provision poudriere
#   ./vm.sh start | stop | status
#   ./vm.sh ssh [cmd...]        ssh into the VM (root)
#   ./vm.sh console             attach to the serial console (nc; ~. does not work, use ^C)
#   ./vm.sh qa <port-qa.sh args>  run scripts/port-qa.sh in the VM, fetch results
#   ./vm.sh update-ports        git pull the ports tree inside the VM
#   ./vm.sh snapshot [name] | restore [name] | snapshots
#   ./vm.sh destroy             delete the VM disk (keeps downloaded image cache)
#
# Configuration (environment variables):
#   PORTVM_DIR      VM state directory       (default: ~/.freebsd-portvm)
#   PORTVM_RELEASE  FreeBSD release          (default: latest — resolved from
#                                             download.freebsd.org at setup)
#   PORTVM_SSH_PORT host port forwarded to VM:22 (default: 2222)
#   PORTVM_HTTP_PORT host port for the setup-time key handoff (default: ssh port + 1)
#   PORTVM_CPUS     vCPUs                    (default: host cores - 2, min 2)
#   PORTVM_MEM      RAM                      (default: 8G)
#   PORTVM_DISK     disk size                (default: 60G)
#   PORTVM_PUBKEY   ssh public key file      (default: first of ~/.ssh/id_*.pub)

# Explicit error handling rather than blanket errexit — every step that
# matters checks its own status via die().
set -u

PORTVM_DIR="${PORTVM_DIR:-$HOME/.freebsd-portvm}"
RELEASE="${PORTVM_RELEASE:-latest}"
SSH_PORT="${PORTVM_SSH_PORT:-2222}"
HTTP_PORT="${PORTVM_HTTP_PORT:-$(( SSH_PORT + 1 ))}"
MEM="${PORTVM_MEM:-8G}"
DISK_SIZE="${PORTVM_DISK:-60G}"
CPUS="${PORTVM_CPUS:-$(( $(sysctl -n hw.ncpu) - 2 ))}"
(( CPUS >= 2 )) || CPUS=2

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK="$PORTVM_DIR/disk.qcow2"
PIDFILE="$PORTVM_DIR/qemu.pid"
CONSOLE_LOG="$PORTVM_DIR/console.log"
SERIAL_SOCK="$PORTVM_DIR/serial.sock"   # unix sockets cap at ~104 bytes, keep it short
CACHE="$PORTVM_DIR/cache"

case "$(uname -m)" in
  arm64)
    QEMU=qemu-system-aarch64
    IMG_ARCH="arm64-aarch64"; URL_ARCH="aarch64"
    MACHINE_ARGS=(-machine virt -accel hvf -cpu host)
    ;;
  x86_64)
    QEMU=qemu-system-x86_64
    IMG_ARCH="amd64"; URL_ARCH="amd64"
    MACHINE_ARGS=(-machine q35 -accel hvf -cpu host)
    ;;
  *) echo "ERROR: unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac

# "latest" pins itself at setup time to the newest published release, so the
# tooling never rots onto an EOL version the ports tree refuses to build on.
resolve_release() {
  [[ $RELEASE == latest ]] || return 0
  RELEASE=$(curl -fsL https://download.freebsd.org/releases/VM-IMAGES/ \
    | grep -oE '[0-9]+\.[0-9]+-RELEASE' | sort -uV | tail -1 | sed 's/-RELEASE//')
  [[ -n $RELEASE ]] || die "could not determine the latest FreeBSD release"
  say "latest FreeBSD release: $RELEASE"
}

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "==> $*"; }

find_pubkey() {
  if [[ -n "${PORTVM_PUBKEY:-}" ]]; then
    [[ -f "$PORTVM_PUBKEY" ]] || die "PORTVM_PUBKEY=$PORTVM_PUBKEY not found"
    echo "$PORTVM_PUBKEY"; return
  fi
  local k
  for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
    [[ -f $k ]] && { echo "$k"; return; }
  done
  die "no ssh public key found in ~/.ssh (set PORTVM_PUBKEY)"
}

# IdentitiesOnly matters: with an agent holding several keys, ssh exhausts the
# server's MaxAuthTries before it ever offers the right one.
PUBKEY_FILE=$(find_pubkey 2>/dev/null) || PUBKEY_FILE=""
COMMON_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
[[ -n $PUBKEY_FILE && -f ${PUBKEY_FILE%.pub} ]] \
  && COMMON_OPTS+=(-o IdentitiesOnly=yes -i "${PUBKEY_FILE%.pub}")
SSH_OPTS=(-p "$SSH_PORT" "${COMMON_OPTS[@]}")
SCP_OPTS=(-P "$SSH_PORT" "${COMMON_OPTS[@]}")
vssh() { ssh "${SSH_OPTS[@]}" root@localhost "$@"; }

vm_running() { [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

bios_args() {
  # aarch64 needs an EDK2 firmware blob; x86_64 uses the default SeaBIOS.
  if [[ $QEMU == qemu-system-aarch64 ]]; then
    local fw
    fw="$(dirname "$(dirname "$(command -v $QEMU)")")/share/qemu/edk2-aarch64-code.fd"
    [[ -f $fw ]] || die "EDK2 firmware not found at $fw"
    echo "-bios" "$fw"
  fi
}

# First-boot root access, without cloud-init: official FreeBSD VM images
# allow root login on the serial console with an empty password. nuageinit
# (14.x) silently ignores runcmd and cannot enable root ssh, so we drive the
# console directly — deterministic on any official image.
#
# Console input has two traps this works around: the emulated UART drops
# characters when input arrives faster than the guest drains it (so sends
# are throttled and kept short — the ssh key travels over the NAT network
# via a temporary localhost HTTP server instead of being typed), and the
# tty echoes every typed line (so the success marker is spelled in a way
# that only the *executed* output can contain it).
console_bootstrap() {
  local keydir http_pid
  keydir=$(mktemp -d) || die "mktemp failed"
  cp "$PUBKEY_FILE" "$keydir/authorized_keys" || die "could not stage pubkey"
  (cd "$keydir" && exec python3 -m http.server --bind 127.0.0.1 "$HTTP_PORT") >/dev/null 2>&1 &
  http_pid=$!

  say "configuring root ssh over the serial console"
  local rc=0
  python3 - "$SERIAL_SOCK" "$HTTP_PORT" <<'PYEOF' || rc=$?
import socket, sys, time

sock_path, http_port = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.settimeout(1)
buf = b""

def read_until(needle, timeout, nudge=False):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        if needle in buf:
            return True
        try:
            data = s.recv(4096)
            if data:
                buf += data
        except socket.timeout:
            if nudge:  # a getty that booted before we connected needs a wake-up
                s.sendall(b"\r")
    return False

def send(line):
    data = line.encode() + b"\r"
    for i in range(0, len(data), 16):  # throttle: the UART drops floods
        s.sendall(data[i:i + 16])
        time.sleep(0.02)

if not read_until(b"login:", 300, nudge=True):
    sys.exit("no login prompt on serial console within 300s")
send("root")
time.sleep(2)
if buf.rstrip().endswith(b"Password:"):
    send("")
buf = b""
if not read_until(b"root@", 30):
    sys.exit("root console login failed (image has a root password set?)")

# 10.0.2.2 is the host as seen from qemu user-mode networking.
for cmd in [
    "mkdir -p /root/.ssh",
    "fetch -o /root/.ssh/authorized_keys http://10.0.2.2:%s/authorized_keys" % http_port,
    "chmod 700 /root/.ssh",
    "chmod 600 /root/.ssh/authorized_keys",
    "grep -c ssh- /root/.ssh/authorized_keys",
    "echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config",
    "sysrc hostname=portvm sshd_enable=YES",
    "hostname portvm",
    "service sshd restart",
]:
    buf = b""
    # the tty echo shows MARKER''_OK; only real execution prints MARKER_OK
    send(cmd + " && echo MARKER''_OK")
    if not read_until(b"MARKER_OK", 60):
        sys.exit("console command failed: " + cmd)
send("exit")
PYEOF

  kill "$http_pid" 2>/dev/null
  rm -rf "$keydir"
  [[ $rc -eq 0 ]] || die "console bootstrap failed — check $CONSOLE_LOG"
}

cmd_setup() {
  command -v "$QEMU" >/dev/null || die "$QEMU not found — install with: brew install qemu"
  command -v python3 >/dev/null || die "python3 is required for the first-boot console bootstrap"
  mkdir -p "$PORTVM_DIR" "$CACHE"

  [[ -n $PUBKEY_FILE ]] || find_pubkey >/dev/null   # dies with the real message
  say "using ssh key: $PUBKEY_FILE"

  resolve_release
  IMAGE="FreeBSD-${RELEASE}-RELEASE-${IMG_ARCH}-BASIC-CLOUDINIT-zfs.qcow2.xz"
  IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${RELEASE}-RELEASE/${URL_ARCH}/Latest/${IMAGE}"

  if [[ ! -f "$CACHE/$IMAGE" ]]; then
    say "downloading $IMAGE (~600 MB)"
    curl -fL --progress-bar -o "$CACHE/$IMAGE.part" "$IMAGE_URL" \
      || die "download failed: $IMAGE_URL"
    mv "$CACHE/$IMAGE.part" "$CACHE/$IMAGE" || die "could not move image into cache"
  else
    say "using cached image: $CACHE/$IMAGE"
  fi

  [[ -f $DISK ]] && die "VM disk already exists at $DISK — run './vm.sh destroy' first to rebuild"

  say "creating VM disk ($DISK_SIZE)"
  xz -dkc "$CACHE/$IMAGE" > "$DISK" || die "failed to decompress image"
  qemu-img resize "$DISK" "$DISK_SIZE" >/dev/null || die "qemu-img resize failed"

  cmd_start
  console_bootstrap "$(cat "$PUBKEY_FILE")"
  wait_for_ssh 120

  say "provisioning (pkg, poudriere, ports tree, build jail) — takes a while on first run"
  vssh sh -s <<'PROVISION' || die "provisioning failed"
set -ux
error() { code=$1; shift; echo "ERROR: $*" >&2; exit "$code"; }
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f || error 1 "pkg bootstrap failed"
pkg install -y git poudriere portlint portfmt || error 1 "pkg install failed"

mkdir -p /var/cache/poudriere/distfiles || error 1 "mkdir distfiles cache failed"
cat > /usr/local/etc/poudriere.conf <<'CONF'
ZPOOL=zroot
BASEFS=/usr/local/poudriere
FREEBSD_HOST=https://download.freebsd.org
RESOLV_CONF=/etc/resolv.conf
USE_TMPFS=data
DISTFILES_CACHE=/var/cache/poudriere/distfiles
# Fetch official packages for build/run dependencies instead of compiling
# them from source — this is what keeps testport fast for small ports.
PACKAGE_FETCH_BRANCH=latest
CONF

poudriere ports -l | grep -q '^default ' \
  || poudriere ports -c -m git+https -p default \
  || error 1 "poudriere ports tree creation failed"
poudriere jail -lnq | grep -q . \
  || poudriere jail -c -j qa -v "$(uname -r | sed 's/-p[0-9]*$//')" \
  || error 1 "poudriere jail creation failed"
PROVISION

  say "taking 'pristine' snapshot"
  cmd_stop
  qemu-img snapshot -c pristine "$DISK" || die "snapshot failed"
  say "setup complete — './vm.sh start' then './vm.sh qa -o category/port -v x.y.z'"
}

cmd_start() {
  vm_running && { say "VM already running (pid $(cat "$PIDFILE"))"; return; }
  [[ -f $DISK ]] || die "no VM disk — run './vm.sh setup' first"
  say "starting VM ($CPUS cpus, $MEM RAM, ssh on localhost:$SSH_PORT)"
  rm -f "$SERIAL_SOCK"
  # The serial console is exposed as a unix socket AND logged to a file:
  # the socket drives the first-boot bootstrap and `vm.sh console`.
  # shellcheck disable=SC2046
  "$QEMU" \
    "${MACHINE_ARGS[@]}" $(bios_args) \
    -smp "$CPUS" -m "$MEM" \
    -drive if=virtio,file="$DISK",format=qcow2 \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
    -device virtio-net,netdev=n0 \
    -display none -daemonize \
    -pidfile "$PIDFILE" \
    -chardev "socket,id=ser0,path=$SERIAL_SOCK,server=on,wait=off,logfile=$CONSOLE_LOG" \
    -serial chardev:ser0 \
    || die "qemu failed to start (see $CONSOLE_LOG)"
}

wait_for_ssh() {
  local timeout="${1:-120}" waited=0
  say "waiting for ssh (up to ${timeout}s)"
  until ssh "${SSH_OPTS[@]}" -o ConnectTimeout=3 root@localhost true 2>/dev/null; do
    sleep 5; waited=$(( waited + 5 ))
    (( waited < timeout )) || die "VM did not become reachable — check $CONSOLE_LOG"
  done
  say "VM is up"
}

cmd_stop() {
  vm_running || { say "VM not running"; return; }
  say "shutting down VM"
  vssh poweroff 2>/dev/null || true
  local waited=0
  while vm_running && (( waited < 60 )); do sleep 2; waited=$(( waited + 2 )); done
  if vm_running; then
    say "graceful shutdown timed out, killing qemu"
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
}

cmd_status() {
  if vm_running; then
    echo "running (pid $(cat "$PIDFILE"), ssh -p $SSH_PORT root@localhost)"
  else
    echo "stopped"
  fi
}

cmd_ssh() {
  vm_running || die "VM not running — './vm.sh start' first"
  exec ssh "${SSH_OPTS[@]}" root@localhost "$@"
}

cmd_console() {
  vm_running || die "VM not running — './vm.sh start' first"
  say "attaching to serial console (interrupt with ^C; log in as root, empty password)"
  exec nc -U "$SERIAL_SOCK"
}

cmd_qa() {
  vm_running || { cmd_start; }
  wait_for_ssh 120
  say "running port-qa.sh in the VM: $*"
  scp "${SCP_OPTS[@]}" "$REPO_DIR/scripts/port-qa.sh" root@localhost:/root/port-qa.sh \
    || die "failed to copy port-qa.sh into the VM"
  local rc=0
  vssh sh /root/port-qa.sh -O /root/port-qa-output "$@" || rc=$?
  local results="$REPO_DIR/results/$(date +%Y-%m-%d_%H%M%S)"
  mkdir -p "$results"
  scp -r "${SCP_OPTS[@]}" 'root@localhost:/root/port-qa-output/*' "$results/" 2>/dev/null || true
  vssh rm -rf /root/port-qa-output
  say "results copied to $results"
  return $rc
}

cmd_update_ports() {
  vm_running || die "VM not running — './vm.sh start' first"
  say "updating ports tree in VM"
  vssh poudriere ports -u -p default
}

cmd_snapshot()  { cmd_stop; qemu-img snapshot -c "${1:-manual-$(date +%Y%m%d%H%M%S)}" "$DISK" || die "snapshot failed"; say "snapshot taken"; }
cmd_restore()   { cmd_stop; qemu-img snapshot -a "${1:-pristine}" "$DISK" || die "restore failed"; say "restored snapshot '${1:-pristine}'"; }
cmd_snapshots() { qemu-img snapshot -l "$DISK"; }

cmd_destroy() {
  cmd_stop
  rm -f "$DISK" "$CONSOLE_LOG" "$SERIAL_SOCK"
  say "VM disk deleted (image cache kept in $CACHE)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  setup)        cmd_setup "$@" ;;
  start)        cmd_start "$@" ;;
  stop)         cmd_stop "$@" ;;
  status)       cmd_status "$@" ;;
  ssh)          cmd_ssh "$@" ;;
  console)      cmd_console "$@" ;;
  qa)           cmd_qa "$@" ;;
  update-ports) cmd_update_ports "$@" ;;
  snapshot)     cmd_snapshot "$@" ;;
  restore)      cmd_restore "$@" ;;
  snapshots)    cmd_snapshots "$@" ;;
  destroy)      cmd_destroy "$@" ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
