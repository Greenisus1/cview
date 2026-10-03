#!/bin/sh
# Starts everything on the Pi and on every boot: tunnel, Crunchbyte site, model warm-up.
# Run as root. The tunnel token is read from /root/tunnel-token.txt and is never put in this file.
set -e
R=${CB_ROOT:-/root}
U=${CB_UNITS:-/etc/systemd/system}
SC=systemctl
[ -n "$CB_DRY" ] && SC=true
if [ ! -s "$R/tunnel-token.txt" ]; then
  echo "Missing $R/tunnel-token.txt. Create it first (see steps), then run this again."
  exit 1
fi
if [ ! -x "$R/cloudflared-crunchbyte-test" ]; then
  echo "Missing $R/cloudflared-crunchbyte-test"
  exit 1
fi
SITE=$(ls $R/crunchbyte-test-v*.py 2>/dev/null | sort -V | tail -n 1 || true)
if [ -z "$SITE" ]; then
  echo "No crunchbyte-test-v file found in $R"
  exit 1
fi
echo "Site file: $SITE"
chmod 600 $R/tunnel-token.txt
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
$SC enable ollama 2>/dev/null || true
$SC start ollama 2>/dev/null || true
$SC enable shortsite 2>/dev/null || true
$SC start shortsite 2>/dev/null || true
$SC enable cbtunnel crunchbyte cbwarm
$SC restart cbtunnel
$SC restart crunchbyte
$SC restart --no-block cbwarm
sleep 3
for n in ollama shortsite cbtunnel crunchbyte cbwarm; do
  echo "$n: $($SC is-active $n 2>&1)"
done
echo "Done. Check https://crunchbytes.dpdns.org/ in a minute. The model warm-up can take a few minutes."
