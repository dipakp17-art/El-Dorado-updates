#!/data/data/com.termux/files/usr/bin/bash
# El Dorado server care — one-time install on a server phone (the pad or the backup):
#   curl -sLo c.sh dipakp17-art.github.io/El-Dorado-updates/ed_care_install.sh && bash c.sh
# After this, the server follows the admin's setting from the app by itself (see ed_care.sh).
H=$HOME
D=$H/eldorado-care
mkdir -p "$D" "$H/.termux/boot"
command -v openssl >/dev/null || { echo "installing openssl (a minute)…"; yes | pkg install -y openssl-tool >/dev/null 2>&1; }
command -v openssl >/dev/null || { echo "STOP: openssl didn't install — check the internet and run this again"; exit 1; }
curl -sfLo "$D/ed_care.sh" https://dipakp17-art.github.io/El-Dorado-updates/ed_care.sh || { echo "STOP: couldn't download ed_care.sh"; exit 1; }
head -1 "$D/ed_care.sh" | grep -q bash || { echo "STOP: the download looks wrong"; exit 1; }
chmod 700 "$D/ed_care.sh"
# the admin's PUBLIC key — only settings signed by the admin are followed
cat > "$D/admin.pem" <<'PEM'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEq+1iJFyITsuGCKKUPo1yvwg0t+Yf
m9Rv3hfv4cag9U7cR6VLHfim9T26s6HWceVtbzzLkrDPBmtFcKZTA19WnA==
-----END PUBLIC KEY-----
PEM
START='pgrep -f "eldorado-care/ed_care.sh" >/dev/null || (nohup bash $HOME/eldorado-care/ed_care.sh >/dev/null 2>&1 &)'
# start again after a restart (Termux:Boot), and whenever Termux opens
printf '#!/data/data/com.termux/files/usr/bin/sh\nsleep 40\n%s\n' "$START" > "$H/.termux/boot/start-care.sh"
chmod 700 "$H/.termux/boot/start-care.sh"
grep -q "eldorado-care/ed_care.sh" "$H/.bashrc" 2>/dev/null || printf '\n# El Dorado server care\n%s\n' "$START" >> "$H/.bashrc"
pkill -f "eldorado-care/ed_care.sh"; rm -f "$D/pid"
nohup bash "$D/ed_care.sh" >/dev/null 2>&1 &
sleep 3
pgrep -f "eldorado-care/ed_care.sh" >/dev/null && echo "ED-CARE-DONE: server care is running" || echo "STOP: server care didn't start"
