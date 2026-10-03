#!/bin/sh
# One script to set up everything on the Pi: model, tunnel, Crunchbyte site, short-link site, autostart on boot.
# Run as root: wget the file, then: sh install-all.sh
# The tunnel token is typed into a hidden prompt and saved to /root/tunnel-token.txt. It is never part of this file.
R=${CB_ROOT:-/root}
U=${CB_UNITS:-/etc/systemd/system}
RAW=https://raw.githubusercontent.com/Greenisus1/cview/main
SC=systemctl
[ -n "$CB_DRY" ] && SC=true
say() { echo "== $1"; }
die() { echo "STOP: $1"; exit 1; }

say "Checking basics"
command -v python3 >/dev/null || die "python3 is missing (apt install -y python3)"
command -v wget >/dev/null || die "wget is missing"

say "Tunnel token"
if [ ! -s "$R/tunnel-token.txt" ]; then
  printf "Paste the Cloudflare tunnel token (hidden), then press Enter: "
  stty -echo 2>/dev/null || true
  read T
  stty echo 2>/dev/null || true
  echo
  [ -n "$T" ] || die "no token entered"
  ( umask 077; echo "$T" > "$R/tunnel-token.txt" )
  T=
fi
chmod 600 "$R/tunnel-token.txt"

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
ExecStart=/bin/sh -c '$R/cloudflared-crunchbyte-test tunnel run --token \$\$(cat $R/tunnel-token.txt)'
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
$SC daemon-reload
$SC disable --now cloudflared 2>/dev/null || true
$SC enable shortsite 2>/dev/null || true
$SC start shortsite 2>/dev/null || true
$SC enable cbtunnel crunchbyte cbwarm
$SC restart cbtunnel
$SC restart crunchbyte
$SC restart --no-block cbwarm
sleep 3
FAIL=""
for n in ollama shortsite cbtunnel crunchbyte cbwarm; do
  S=$($SC is-active $n 2>&1)
  echo "$n: $S"
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
echo "Check https://crunchbytes.dpdns.org/ in a minute. The model warm-up can take a few minutes."
