#!/data/data/com.termux/files/usr/bin/bash
# El Dorado: keep messages and files on this server for 30 days (was 12 h / 3 days / 7 days).
#   bash /sdcard/Download/ed_keep30days.sh
# Changes only ~/ntfy/server.yml (a copy of the old one is kept), then restarts the server.
# 30 days of photos, videos and nightly backups need room: the file space allowed is set from
# this phone's free storage (half of it, between 2 and 20 GB), so the phone never fills up.
Y=$HOME/ntfy/server.yml
[ -f "$Y" ] || { echo "STOP: $Y not found"; exit 1; }
cp -n "$Y" "$Y.before-30days"
set_key() {   # set_key name value — replace the line, or add it
  if grep -q "^$1:" "$Y"; then sed -i "s|^$1:.*|$1: \"$2\"|" "$Y"; else echo "$1: \"$2\"" >> "$Y"; fi
}
FREE_GB=$(( $(df -k "$HOME" | awk 'NR==2{print $4}') / 1024 / 1024 ))
ROOM=$(( FREE_GB / 2 )); [ $ROOM -gt 20 ] && ROOM=20; [ $ROOM -lt 2 ] && ROOM=2
echo "free storage: ${FREE_GB} GB -> files may use up to ${ROOM} GB"
set_key cache-duration 720h
set_key attachment-expiry-duration 720h
set_key attachment-total-size-limit "${ROOM}G"
set_key visitor-attachment-total-size-limit "${ROOM}G"
echo "settings now:"; grep -E "^(cache-duration|attachment-expiry-duration|attachment-total-size-limit|visitor-attachment-total-size-limit):" "$Y"

echo "restarting the server…"
pkill -f "ntfy-bin serve"; sleep 2
if [ -f "$HOME/.termux/boot/start-ntfy.sh" ]; then
  bash "$HOME/.termux/boot/start-ntfy.sh" >/dev/null 2>&1 &          # the pad
else
  nohup "$HOME/ntfy/ntfy-bin" serve --config "$Y" >> "$HOME/ntfy.log" 2>&1 &   # the backup phone
fi
for i in $(seq 20); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/health)" = 200 ] && { echo "ED-30DAYS-DONE: server running, keeps messages 30 days"; exit 0; }
  sleep 1
done
echo "STOP: the server didn't come back — run:  bash ~/.termux/boot/start-ntfy.sh"
