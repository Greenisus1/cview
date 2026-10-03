#!/bin/sh
# One script to set up everything on the Pi: model, tunnel, Crunchbyte site, short-link site, autostart on boot.
# Run as root: wget the file, then: sh RUNAPPS2.sh
# Lets you select a saved key by number; never displays its value.
# Only the runtime tunnel token is exported to a mode-600 file; the master is never saved.
# Without a vault, keeps an existing token or asks for one using a hidden prompt.
R=${CB_ROOT:-/root}
U=${CB_UNITS:-/etc/systemd/system}
RAW=https://raw.githubusercontent.com/Greenisus1/cview/main
RUN_ONLY=0
[ "$1" = "--run-only" ] && RUN_ONLY=1
SC=systemctl
[ -n "$CB_DRY" ] && SC=true
TOTAL=6
[ "$RUN_ONLY" = 1 ] && TOTAL=3
COUNT=0
say() {
  COUNT=$((COUNT + 1))
  printf '\n  [%s/%s] %s\n  ------------------------------------------\n' "$COUNT" "$TOTAL" "$1"
}
die() { echo "STOP: $1"; exit 1; }

printf "\n  Crunchbyte setup - installer 4\n  Your saved keys stay in the encrypted vault.\n"
say "Checking basics"
command -v python3 >/dev/null || die "python3 is missing (apt install -y python3)"
command -v wget >/dev/null || die "wget is missing"

say "Tunnel tokens"
umask 077
NEED_AI=0
NEED_SHORT=0
[ -s "$R/tunnel-token.txt" ] || NEED_AI=1
[ -s "$R/tunnel-token-short.txt" ] || NEED_SHORT=1
if [ "$NEED_AI" = 0 ] && [ "$NEED_SHORT" = 0 ]; then
  echo "  Using the saved private tunnel tokens."
elif [ -s "$R/.keyvault" ]; then
  [ -f "$R/keys2.py" ] || die "keys2.py is missing; download it beside this installer"
  # Unlock once, show names only, and atomically export the chosen tokens.
  NEED_AI=$NEED_AI NEED_SHORT=$NEED_SHORT KEYVAULT_FILE="$R/.keyvault" python3 - "$R" <<'PYVAULT'
import importlib.util, os, sys, tempfile, warnings, getpass
root = sys.argv[1]
warnings.simplefilter('error', getpass.GetPassWarning)
def safe_name(name):
    return ''.join(c if c.isprintable() else '?' for c in name)
def pick(data, tty_in, tty, title, hint, prefer):
    names = sorted(data)
    if prefer and prefer in data:
        tty.write('\n  Using saved key "%s" for the %s.\n' % (safe_name(prefer), title))
        tty.flush()
        return prefer
    tty.write('\n  +------------------------------------------+\n')
    tty.write('  | Choose the %-30s |\n' % (title + ' key'))
    tty.write('  +------------------------------------------+\n')
    tty.write('  Key names only. Values stay hidden.\n\n')
    for i, name in enumerate(names, 1):
        tty.write('    %2d. %s\n' % (i, safe_name(name)))
    tty.write('\n  %s\n' % hint)
    tty.flush()
    while True:
        tty.write('  Key number (q = cancel): ')
        tty.flush()
        answer = tty_in.readline().strip()
        if not answer or answer.lower() == 'q':
            sys.exit('Cancelled; existing token was not changed.')
        if answer.isascii() and answer.isdecimal() and 1 <= int(answer) <= len(names):
            return names[int(answer) - 1]
        tty.write('  Enter a number from 1 to %d.\n' % len(names))
        tty.flush()
def export(data, name, outname):
    token = data[name]
    if not isinstance(token, str):
        sys.exit('Selected entry is not text; choose a Cloudflare tunnel token.')
    token = token.strip()
    if not token.startswith('eyJ') or any(c.isspace() for c in token):
        sys.exit('Selected entry is not a tunnel token. Save only the long eyJ token, not an ID or install command.')
    fd, path = tempfile.mkstemp(prefix='.tunnel-token-', dir=root)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(token)
            f.flush()
            os.fsync(f.fileno())
        os.replace(path, os.path.join(root, outname))
    finally:
        if os.path.exists(path):
            os.unlink(path)
    print('  Saved selected key to %s (private, mode 600).' % outname)
try:
    spec = importlib.util.spec_from_file_location('pi_keys', os.path.join(root, 'keys2.py'))
    vault = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(vault)
    data, master = vault.load()
    del master
    if not isinstance(data, dict) or not data:
        sys.exit('Vault is empty. Save the tunnel tokens in the keys app first.')
    # Python source arrives on stdin; always read choices from the real terminal.
    with open('/dev/tty', 'r') as tty_in, open('/dev/tty', 'w') as tty:
        if os.environ.get('NEED_AI') == '1':
            name = pick(data, tty_in, tty, 'AI site tunnel', 'Select the AI tunnel, not the shortener tunnel.', None)
            export(data, name, 'tunnel-token.txt')
        if os.environ.get('NEED_SHORT') == '1':
            name = pick(data, tty_in, tty, 'shortener tunnel', 'Select the link shortener tunnel, not the AI tunnel.', 'cloudflare-short')
            export(data, name, 'tunnel-token-short.txt')
    del data
except (KeyboardInterrupt, EOFError, getpass.GetPassWarning):
    sys.exit('Cancelled. No secret was displayed or changed.')
except (OSError, ValueError, TypeError):
    sys.exit('Could not read the vault or save the token. Check keys2.py and vault file permissions.')
PYVAULT
  [ $? -eq 0 ] || die "key selection/export failed; existing tokens were kept. Fix the entry or password and rerun"
else
  for T in tunnel-token.txt tunnel-token-short.txt; do
    [ -s "$R/$T" ] && continue
    echo "  Missing $T"
    python3 - "$R/$T" <<'PYTOKEN'
import getpass, os, sys, tempfile, warnings
warnings.simplefilter("error", getpass.GetPassWarning)
try:
    token = getpass.getpass("Paste the Cloudflare tunnel token for this file (hidden), then press Enter: ").strip()
    if not token or any(c.isspace() for c in token):
        sys.exit("Enter only the token, not the tunnel command.")
    fd, path = tempfile.mkstemp(prefix=".tunnel-token-", dir=os.path.dirname(sys.argv[1]))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(token)
        os.chmod(path, 0o600)
        os.replace(path, sys.argv[1])
    finally:
        if os.path.exists(path):
            os.unlink(path)
except (KeyboardInterrupt, EOFError, getpass.GetPassWarning):
    sys.exit("No hidden token entered; cancelled.")
PYTOKEN
    [ $? -eq 0 ] || die "no token saved"
  done
fi
chmod 600 "$R/tunnel-token.txt" "$R/tunnel-token-short.txt" || die "could not protect the token files"

if [ "$RUN_ONLY" = 0 ]; then
say "Tunnel program"
if [ ! -x "$R/cloudflared-crunchbyte-test" ]; then
  case $(uname -m) in
    aarch64|arm64) CF=cloudflared-linux-arm64 ;;
    armv7l|armv6l) CF=cloudflared-linux-arm ;;
    x86_64) CF=cloudflared-linux-amd64 ;;
    *) die "unknown CPU type" ;;
  esac
  wget -q -O "$R/cloudflared-crunchbyte-test" https://github.com/cloudflare/cloudflared/releases/latest/download/$CF || die "could not download the tunnel program"
  chmod +x "$R/cloudflared-crunchbyte-test"
fi

say "Ollama and model"
if ! command -v ollama >/dev/null; then
  apt-get install -y zstd >/dev/null 2>&1 || true
  wget -q -O "$R/ollama-install.sh" https://ollama.com/install.sh || die "could not download the Ollama installer"
  sh "$R/ollama-install.sh" || die "Ollama install failed"
fi
$SC enable ollama 2>/dev/null || true
$SC start ollama 2>/dev/null || true
sleep 3
if ! ollama list 2>/dev/null | grep -q "qwen3:8b"; then
  echo "Downloading qwen3:8b (about 5 GB, can take a while)"
  ollama pull qwen3:8b || die "model download failed"
fi

say "Site file"
step() {
  # step PATCHNAME SOURCE_FILE RESULT_FILE
  if [ ! -f "$R/$3" ]; then
    [ -f "$R/$2" ] || die "$2 is missing, cannot build $3"
    wget -q -O "$R/$1.py" "$RAW/$1.py" || die "could not download $1.py"
    ( cd $R && python3 $1.py ) || die "$1 failed"
  fi
}
if [ ! -f "$R/crunchbyte-test-v11.py" ]; then
  step cbpatch8 crunchbyte-test-v3.py crunchbyte-test-v7.py
  step cbpatch10 crunchbyte-test-v7.py crunchbyte-test-v8.py
  step cbpatch11 crunchbyte-test-v8.py crunchbyte-test-v9.py
  step cbpatch12 crunchbyte-test-v9.py crunchbyte-test-v10.py
  step cbpatch13 crunchbyte-test-v10.py crunchbyte-test-v11.py
fi

say "Services"
SITE=$(ls $R/crunchbyte-test-v*.py 2>/dev/null | sort -V | tail -n 1 || true)
if [ -z "$SITE" ]; then
  echo "No crunchbyte-test-v file found in $R"
  exit 1
fi
echo "Site file: $SITE"
if [ ! -s "$R/.crunchbyte-github.json" ]; then
  echo "Owner sign-in setup (press Enter for the Client ID, paste the secret hidden; Enter alone skips)"
  python3 $SITE --setup-github || echo "Skipped owner sign-in. Run later: python3 $SITE --setup-github"
fi
mkdir -p $U
cat > $U/cbtunnel.service <<UNIT
[Unit]
Description=Crunchbyte tunnel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/sh -c '$R/cloudflared-crunchbyte-test tunnel run --token \$(cat $R/tunnel-token.txt)'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
cat > $U/shorttunnel.service <<UNIT
[Unit]
Description=Link shortener tunnel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/sh -c '$R/cloudflared-crunchbyte-test tunnel run --token \$(cat $R/tunnel-token-short.txt)'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
cat > $U/crunchbyte.service <<UNIT
[Unit]
Description=Crunchbyte AI site
After=network-online.target ollama.service
Wants=ollama.service

[Service]
Environment=HOME=$R
WorkingDirectory=$R
ExecStart=/usr/bin/python3 $SITE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
cat > $U/cbwarm.service <<UNIT
[Unit]
Description=Keep qwen3:8b loaded
After=ollama.service
Wants=ollama.service

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=900
ExecStartPre=/bin/sleep 20
ExecStart=/usr/bin/wget -q -O /dev/null --timeout=800 --post-data={\"model\":\"qwen3:8b\",\"keep_alive\":-1} http://127.0.0.1:11434/api/generate

[Install]
WantedBy=multi-user.target
UNIT
$SC daemon-reload || die "could not reload services"
$SC disable --now cloudflared 2>/dev/null || true
$SC enable shortsite 2>/dev/null || true
$SC start shortsite 2>/dev/null || true
$SC enable cbtunnel crunchbyte cbwarm || die "could not enable AI services"
$SC enable shorttunnel || die "could not enable the shortener tunnel"
# Keep a local copy so RUNAPPS never needs GitHub again.
BIN=${CB_BIN:-/usr/local/bin}
LIB=${CB_LIB:-/usr/local/lib/crunchbyte}
mkdir -p "$BIN" "$LIB" || die "could not create RUNAPPS directories"
cp "$0" "$LIB/RUNAPPS.sh" || die "could not save RUNAPPS locally"
chmod 700 "$LIB/RUNAPPS.sh"
cat > "$BIN/RUNAPPS" <<WRAPPER
#!/bin/sh
exec /bin/sh "$LIB/RUNAPPS.sh" --run-only
WRAPPER
chmod 755 "$BIN/RUNAPPS" || die "could not install RUNAPPS command"
fi
if [ "$RUN_ONLY" = 1 ]; then
  say "Starting apps"
  $SC start ollama || die "could not start Ollama"
  $SC restart shortsite || die "could not start the link shortener"
fi
$SC restart cbtunnel || die "could not start the AI tunnel"
$SC restart shorttunnel || die "could not start the shortener tunnel"
$SC restart crunchbyte || die "could not start the AI site"
$SC restart --no-block cbwarm || die "could not start model warm-up"
sleep 3
FAIL=""
for n in ollama shortsite shorttunnel cbtunnel crunchbyte cbwarm; do
  S=$($SC is-active $n 2>&1)
  printf "  %-14s %s\n" "$n" "$S"
  if [ -z "$CB_DRY" ]; then
    case $n in
      cbwarm) [ "$S" = "active" ] || [ "$S" = "activating" ] || FAIL="$FAIL $n" ;;
      *) [ "$S" = "active" ] || FAIL="$FAIL $n" ;;
    esac
  fi
done
echo
if [ -n "$FAIL" ]; then
  echo "FAILED, not running:$FAIL"
  echo "Look at the reason with: journalctl -u NAME -n 20  (replace NAME with one of the names above)"
  exit 1
fi
echo "Ran successfully"
echo "Next time, type: RUNAPPS"
echo "Check https://crunchbytes.dpdns.org/ and the shortener site in a minute. The model warm-up can take a few minutes."
