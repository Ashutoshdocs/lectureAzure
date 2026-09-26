#!/usr/bin/env bash
# ------------------------------------------------------------------
# DEMO 5 - VNET INTEGRATION (App Service regional VNet integration)
#
# Lesson: the web app still LIVES OUTSIDE our VNet on shared App
#         Service infrastructure and is still reachable on its public
#         URL. VNet integration only gives it an OUTBOUND tunnel into
#         snet-appsvc so IT can call private things in our VNet.
#
# The app is a tiny "caller": every time you open its URL it tries to
# fetch TARGET_URL (the private ACI container from demo 4) and tells
# you whether that worked.
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

TARGET_IP="${ACI_IP:-}"
if [[ -z "$TARGET_IP" ]]; then
  echo "ACI_IP not found. Run ./04-vnet-injection.sh first." >&2; exit 1
fi
TARGET_URL="http://${TARGET_IP}"
APP_URL="https://${WEBAPP}.azurewebsites.net"

step "1. Build the tiny caller app"
APP_SRC="$DEMO_DIR/app"
rm -f /tmp/caller-app.zip
(cd "$APP_SRC" && zip -q -r /tmp/caller-app.zip .)

step "2. Create App Service plan (B1 supports VNet integration) and the web app"
az appservice plan create -g "$RG" -n asp-demo --sku B1 --is-linux -l "$LOCATION" -o none
az webapp create -g "$RG" -p asp-demo -n "$WEBAPP" --runtime "NODE:22-lts" -o none
az webapp config appsettings set -g "$RG" -n "$WEBAPP" --settings TARGET_URL="$TARGET_URL" -o none
az webapp deploy -g "$RG" -n "$WEBAPP" --src-path /tmp/caller-app.zip --type zip -o none

call_app() {
  for i in 1 2 3 4 5 6; do
    out=$(curl -s --max-time 30 "$APP_URL" || true)
    if [[ -n "$out" ]]; then echo "$out" | head -n 8; return; fi
    sleep 10
  done
  echo "(no response yet - app may still be starting; re-run: curl $APP_URL)"
}

step "3. TEST BEFORE integration - open the public URL"
info "Your request reaches the app over the internet (inbound is public)."
info "The app then tries to reach $TARGET_URL ..."
call_app
info "Expected: FAILED - the app lives outside our VNet and can't see 10.1.3.x."

step "4. Turn on VNet integration (outbound tunnel into snet-appsvc)"
az webapp vnet-integration add -g "$RG" -n "$WEBAPP" --vnet "$VNET_CONSUMER" --subnet snet-appsvc -o none
az webapp vnet-integration list -g "$RG" -n "$WEBAPP" --query '[].{vnet:name, subnet:vnetResourceId}' -o table || true
info "Waiting 45s for the integration to take effect..."
sleep 45
az webapp restart -g "$RG" -n "$WEBAPP" -o none
sleep 20

step "5. TEST AFTER integration - open the SAME public URL"
call_app
info "Expected: SUCCESS - the app reached the private container through the VNet."

step "Notice what did NOT change"
info "We still opened $APP_URL from the PUBLIC internet and it answered."
info "VNet integration is OUTBOUND ONLY. To make inbound private too you'd add a"
info "private endpoint to the web app (demo 2 technique) and disable public access."

step "DEMO 5 DONE - you've seen all five! Clean up with ./99-cleanup.sh"
