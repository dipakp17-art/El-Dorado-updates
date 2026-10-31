#!/data/data/com.termux/files/usr/bin/bash
# El Dorado server care — runs in the background on both server phones (the pad and the backup).
#
# Every 10 minutes it:
#  1. repairs itself: if this phone's chat server or its tunnel program stopped, it starts them again;
#  2. watches the OTHER server: if it stops answering, it tells the admin (and again when it's back);
#  3. reads the admin's setting, which the El Dorado app on the admin's phone posts
#     (Settings → Server care), and keeps this server the same way. The setting must be signed with
#     the admin's key — anything else is ignored — and it can only change ONE thing: how many days
#     messages and files are kept (7–30). It can't run commands or install anything.
#  4. keeps itself tidy: trims log files that grow too big, warns when storage runs low, and once a
#     month updates the tunnel program (cloudflared) so Cloudflare keeps accepting it;
#  5. restarts itself when the admin taps "Restart" in the app (also signed with the admin's key).
# Every few hours it also posts a short health note (which server, days kept, free storage).
# Notes and alerts go to a public ntfy.sh topic; the admin's app turns alerts into notifications.
H=$HOME
D=$H/eldorado-care
TOPIC=eldorado-care-2a718a5b97571708
STATUS=eldorado-care-st-393cacb8bd15ffc0
PEM=$D/admin.pem
Y=$H/ntfy/server.yml
MIN_DAYS=7; MAX_DAYS=30
WHO=backup; OTHER=pad; OTHER_BOARD=eldorado-srv-40491b26f336a9be
if [ -f "$H/.termux/boot/start-ntfy.sh" ]; then WHO=pad; OTHER=backup; OTHER_BOARD=eldorado-bak-8ff3cd54c9a75442; fi
mkdir -p "$D"

# only one copy running
if [ -f "$D/pid" ] && kill -0 "$(cat "$D/pid")" 2>/dev/null && [ "$(cat "$D/pid")" != "$$" ]; then exit 0; fi
echo $$ > "$D/pid"
termux-wake-lock 2>/dev/null

log() { echo "$(date '+%F %T') $*" >> "$D/care.log"; tail -n 300 "$D/care.log" > "$D/care.tmp" && mv "$D/care.tmp" "$D/care.log"; }
note() { curl -s -m 30 -o /dev/null -d "$1" "https://ntfy.sh/$STATUS"; }        # a line for the admin's app
alert() { note "al1|$1|$2|$(date +%s)"; log "alert: $1 $2"; }

days_now() { local h; h=$(sed -n 's/^cache-duration: *"\{0,1\}\([0-9]*\)h.*/\1/p' "$Y"); echo $(( ${h:-0} / 24 )); }
free_gb() { echo $(( $(df -k "$H" | awk 'NR==2{print $4}') / 1024 / 1024 )); }
local_ok() { [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/health)" = 200 ]; }

set_key() {   # set_key name value — replace the line, or add it
  if grep -q "^$1:" "$Y"; then sed -i "s|^$1:.*|$1: \"$2\"|" "$Y"; else echo "$1: \"$2\"" >> "$Y"; fi
}

restart_server() {
  pkill -f "ntfy-bin serve"; sleep 2
  if [ "$WHO" = pad ]; then bash "$H/.termux/boot/start-ntfy.sh" >/dev/null 2>&1 &
  else nohup "$H/ntfy/ntfy-bin" serve --config "$Y" >> "$H/ntfy.log" 2>&1 & fi
  for i in $(seq 30); do local_ok && return 0; sleep 1; done
  return 1
}

apply_days() {   # keep messages and files N days; file space = half the free storage, 2–20 GB
  local n=$1 room
  room=$(( $(free_gb) / 2 )); [ $room -gt 20 ] && room=20; [ $room -lt 2 ] && room=2
  cp -n "$Y" "$Y.before-care"
  set_key cache-duration "$(( n * 24 ))h"
  set_key attachment-expiry-duration "$(( n * 24 ))h"
  set_key attachment-total-size-limit "${room}G"
  set_key visitor-attachment-total-size-limit "${room}G"
  if restart_server; then log "now keeping messages $n days (files up to ${room} GB)"
  else log "changed to $n days, but the server didn't come back"; fi
}

# 4. tidy: big logs trimmed in place (programs keep writing to them), storage warning, monthly update
once() {   # once NAME SECONDS — true at most once per SECONDS
  local f="$D/once_$1" now; now=$(date +%s)
  [ $(( now - $(cat "$f" 2>/dev/null || echo 0) )) -ge "$2" ] || return 1
  echo "$now" > "$f"
}
tidy() {
  local f
  for f in "$H"/*.log "$H"/eldorado/*.log "$H"/ntfy/*.log; do
    [ -f "$f" ] || continue
    if [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 5242880 ]; then
      tail -c 1048576 "$f" > "$D/trim.tmp" && cat "$D/trim.tmp" > "$f" && rm -f "$D/trim.tmp"
      log "trimmed $(basename "$f")"
    fi
  done
  [ "$(free_gb)" -lt 3 ] && once storage 43200 && alert "$WHO" storage-low
  if once update 2592000; then                        # every 30 days
    local v1 v2
    v1=$(cloudflared --version 2>/dev/null | head -n 1)
    yes | pkg install --only-upgrade -y cloudflared >/dev/null 2>&1
    v2=$(cloudflared --version 2>/dev/null | head -n 1)
    if [ -n "$v2" ] && [ "$v1" != "$v2" ]; then
      log "tunnel program updated: $v2"
      pkill -f "cloudflared tunnel"                     # the tunnel program starts the new one by itself
      alert "$WHO" updated-tunnel
    fi
  fi
}

# 5. "Restart" from the admin's app: cmd1|restart|<pad|backup>|time|signature
follow_restart() {
  local LINE V C W T SIG LAST now
  LINE=$(curl -s -m 30 "https://ntfy.sh/$TOPIC/raw?poll=1&since=2h" | grep "^cmd1|restart|$WHO|" | tail -n 1)
  [ -n "$LINE" ] || return
  IFS='|' read -r V C W T SIG <<< "$LINE"
  LAST=$(cat "$D/cmd_last" 2>/dev/null || echo 0); now=$(date +%s)
  [[ "$T" =~ ^[0-9]+$ ]] && [ "$T" -gt "$LAST" ] && [ $(( now - T )) -lt 3600 ] || return
  printf '%s' "cmd1|restart|$WHO|$T" > "$D/msg"
  printf '%s' "$SIG" | base64 -d > "$D/sig" 2>/dev/null
  if ! openssl dgst -sha256 -verify "$PEM" -signature "$D/sig" "$D/msg" 2>/dev/null | grep -q "Verified OK"; then
    log "ignored a restart that isn't signed by the admin"; return
  fi
  echo "$T" > "$D/cmd_last"
  log "restarting, as the admin asked"
  restart_server
  pkill -f "cloudflared tunnel"                          # a fresh tunnel too (it comes back by itself)
  alert "$WHO" restarted
}

post_status() { note "st1|$WHO|$(days_now)|$(free_gb)|$(date +%s)"; date +%s > "$D/status_at"; }

# 1. this phone: chat server and tunnel program running?
self_repair() {
  if ! local_ok; then
    sleep 20; local_ok && return          # maybe just restarting
    log "the chat server wasn't answering — starting it again"
    if restart_server; then alert "$WHO" fixed-server; else alert "$WHO" server-broken; fi
  fi
  if ! pgrep -f "eldorado/tunnel.sh" >/dev/null; then
    log "the tunnel program had stopped — starting it again"
    nohup bash "$H/eldorado/tunnel.sh" >> "$H/eldorado/tunnel.log" 2>&1 &
    alert "$WHO" fixed-tunnel
  fi
}

# 2. the other server: answering from the internet?
watch_other() {
  local board url code miss state
  board=$(curl -s -m 30 "https://ntfy.sh/$OTHER_BOARD/raw?poll=1&since=12h") || return     # no internet here: can't judge
  url=$(printf '%s\n' "$board" | grep -o '^https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1)
  code=000; [ -n "$url" ] && code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$url/v1/health")
  miss=$(cat "$D/other_miss" 2>/dev/null || echo 0); state=$(cat "$D/other_state" 2>/dev/null || echo up)
  if [ "$code" = 200 ]; then
    [ "$state" = down ] && alert "$OTHER" up
    echo 0 > "$D/other_miss"; echo up > "$D/other_state"
  else
    miss=$((miss + 1)); echo $miss > "$D/other_miss"
    if [ $miss -ge 2 ] && [ "$state" != down ]; then alert "$OTHER" down; echo down > "$D/other_state"; fi
  fi
}

# 3. the admin's signed setting
follow_setting() {
  local LINE V DAYS T SIG LAST
  LINE=$(curl -s -m 30 "https://ntfy.sh/$TOPIC/raw?poll=1&since=24h" | grep '^care1|' | tail -n 1)
  [ -n "$LINE" ] || return
  IFS='|' read -r V DAYS T SIG <<< "$LINE"
  LAST=$(cat "$D/last" 2>/dev/null || echo 0)
  [[ "$DAYS" =~ ^[0-9]+$ ]] && [[ "$T" =~ ^[0-9]+$ ]] && [ "$T" -gt "$LAST" ] || return
  printf '%s' "care1|$DAYS|$T" > "$D/msg"
  printf '%s' "$SIG" | base64 -d > "$D/sig" 2>/dev/null
  if ! openssl dgst -sha256 -verify "$PEM" -signature "$D/sig" "$D/msg" 2>/dev/null | grep -q "Verified OK"; then
    log "ignored a setting that isn't signed by the admin"; return
  fi
  echo "$T" > "$D/last"
  [ "$DAYS" -lt $MIN_DAYS ] && DAYS=$MIN_DAYS
  [ "$DAYS" -gt $MAX_DAYS ] && DAYS=$MAX_DAYS
  if [ "$(days_now)" != "$DAYS" ]; then apply_days "$DAYS"; post_status; fi
}

log "server care started ($WHO)"
while true; do
  for i in 1 2 3 4; do follow_restart; sleep 120; done
  self_repair
  watch_other
  follow_setting
  follow_restart
  tidy
  [ $(( $(date +%s) - $(cat "$D/status_at" 2>/dev/null || echo 0) )) -ge 10800 ] && post_status   # every 3 hours
  sleep 120
done
