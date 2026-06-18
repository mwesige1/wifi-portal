# ═══════════════════════════════════════════════════════════════
# Optimum WiFi Portal — MikroTik Auto-Provisioning Script
# RouterOS 7.x
# Paste into MikroTik terminal and press Enter
# ═══════════════════════════════════════════════════════════════

# ── EDIT THESE THREE LINES ONLY ────────────────────────────────
:local routerIdentity   "Hotel-Kampala"
:local routerLocation   "Kampala City Hotel"
:local wgIP             "10.0.0.2"
# ═══════════════════════════════════════════════════════════════

# ── FIXED SETTINGS — DO NOT CHANGE ─────────────────────────────
:local portalDomain     "optimuminnovationhotspot.com"
:local portalURL        "https://optimuminnovationhotspot.com"
:local vpsIP            "187.127.69.66"
:local vpsPort          "51820"
:local vpsPubKey        "Lf41C1lyGy9NZxZeXAXGYoEtiPixqJpkA/mOaU8wR0M="
:local wgNetwork        "10.0.0.0/24"
:local lanIP            "192.168.88.1"
:local lanNetwork       "192.168.88.0/24"
:local poolStart        "192.168.88.2"
:local poolEnd          "192.168.88.254"
# ═══════════════════════════════════════════════════════════════

:put ""
:put "═══════════════════════════════════════════════"
:put "  Optimum WiFi — Auto Configuration"
:put "═══════════════════════════════════════════════"
:put ("  Router  : " . $routerIdentity)
:put ("  Location: " . $routerLocation)
:put ("  Tunnel  : " . $wgIP)
:put "═══════════════════════════════════════════════"
:put ""

# ── STEP 1 — Router identity ───────────────────────────────────
:put "Step 1: Setting router identity..."
/system identity set name=$routerIdentity
:put ("  ✅ Identity: " . $routerIdentity)

# ── STEP 2 — Bridge ───────────────────────────────────────────
:put "Step 2: Configuring LAN bridge..."
:if ([:len [/interface bridge find name="bridge1"]] = 0) do={
    /interface bridge add name=bridge1 protocol-mode=rstp
}
:foreach port in={"ether2";"ether3";"ether4";"ether5"} do={
    :if ([:len [/interface bridge port find interface=$port bridge=bridge1]] = 0) do={
        :do { /interface bridge port add interface=$port bridge=bridge1 } on-error={}
    }
}
:if ([:len [/ip address find interface="bridge1"]] = 0) do={
    /ip address add address=($lanIP . "/24") interface=bridge1
}
:put "  ✅ Bridge configured"

# ── STEP 3 — DHCP Server ──────────────────────────────────────
:put "Step 3: Configuring DHCP server..."
:if ([:len [/ip pool find name="dhcp_pool0"]] = 0) do={
    /ip pool add name=dhcp_pool0 ranges=($poolStart . "-" . $poolEnd)
}
:if ([:len [/ip dhcp-server find name="dhcp1"]] = 0) do={
    /ip dhcp-server add name=dhcp1 interface=bridge1 \
        address-pool=dhcp_pool0 lease-time=1h disabled=no
}
:if ([:len [/ip dhcp-server network find address=$lanNetwork]] = 0) do={
    /ip dhcp-server network add address=$lanNetwork \
        gateway=$lanIP dns-server=$lanIP
} else={
    /ip dhcp-server network set [find address=$lanNetwork] \
        gateway=$lanIP dns-server=$lanIP
}
:put "  ✅ DHCP configured — DNS server: router itself"

# ── STEP 4 — NAT ──────────────────────────────────────────────
:put "Step 4: Configuring NAT..."
:if ([:len [/ip firewall nat find chain=srcnat action=masquerade out-interface="ether1"]] = 0) do={
    /ip firewall nat add chain=srcnat action=masquerade \
        out-interface=ether1 comment="Optimum-Internet-Sharing"
}
:put "  ✅ NAT configured"

# ── STEP 5 — WireGuard ────────────────────────────────────────
:put "Step 5: Configuring WireGuard tunnel..."
:if ([:len [/interface wireguard find name="wg0"]] = 0) do={
    /interface wireguard add name=wg0 listen-port=51820
}
:local pubKey [/interface wireguard get wg0 public-key]
:if ([:len [/ip address find interface="wg0"]] = 0) do={
    /ip address add address=($wgIP . "/24") interface=wg0
}
/interface wireguard peers remove [find interface="wg0"]
/interface wireguard peers add \
    interface=wg0 \
    public-key=$vpsPubKey \
    endpoint-address=$vpsIP \
    endpoint-port=$vpsPort \
    allowed-address=$wgNetwork \
    persistent-keepalive=25
:put ("  ✅ WireGuard tunnel → " . $vpsIP)
:put ("  ✅ Router public key: " . $pubKey)

# ── STEP 6 — Enable API ───────────────────────────────────────
:put "Step 6: Enabling MikroTik API..."
/ip service set api disabled=no port=8728
/ip service set api-ssl disabled=yes
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
:put "  ✅ API enabled on port 8728"

# ── STEP 7 — WiFi SSID ────────────────────────────────────────
:put "Step 7: Configuring WiFi..."
:if ([:len [/interface wireless find]] > 0) do={
    /interface wireless set [find] \
        ssid="OPTIMUM HOTSPOT" \
        mode=ap-bridge \
        disabled=no
    :if ([:len [/interface bridge port find interface="wlan1" bridge=bridge1]] = 0) do={
        :do { /interface bridge port add interface=wlan1 bridge=bridge1 } on-error={}
    }
    :put "  ✅ WiFi: OPTIMUM HOTSPOT"
} else={
    :put "  ℹ️  No wireless interface — skipping"
}

# ── STEP 8 — Hotspot profile ──────────────────────────────────
:put "Step 8: Configuring hotspot profile..."
:if ([:len [/ip hotspot profile find name="hsprof1"]] = 0) do={
    /ip hotspot profile add \
        name=hsprof1 \
        hotspot-address=$lanIP \
        dns-name=$lanIP \
        login-by=cookie \
        html-directory=flash/webtune-hotspot \
        http-cookie-lifetime=1d
} else={
    /ip hotspot profile set [find name="hsprof1"] \
        hotspot-address=$lanIP \
        dns-name=$lanIP \
        login-by=cookie \
        http-cookie-lifetime=1d
}
:put "  ✅ Hotspot profile configured"

# ── STEP 9 — Hotspot ──────────────────────────────────────────
:put "Step 9: Setting up hotspot..."
:if ([:len [/ip hotspot find name="hotspot1"]] = 0) do={
    /ip hotspot add \
        name=hotspot1 \
        interface=bridge1 \
        address-pool=dhcp_pool0 \
        profile=hsprof1 \
        idle-timeout=5m \
        disabled=no
} else={
    /ip hotspot enable [find name="hotspot1"]
}
:put "  ✅ Hotspot running on bridge1"

# ── STEP 10 — Walled garden ───────────────────────────────────
:put "Step 10: Configuring walled garden..."
/ip hotspot walled-garden remove [find comment="OptimumWiFi"]

# Portal domain
/ip hotspot walled-garden add dst-host=$portalDomain \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host=("*." . $portalDomain) \
    action=allow comment="OptimumWiFi"

# Apple captive portal detection
/ip hotspot walled-garden add dst-host="captive.apple.com" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="*.apple.com" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="gsp1.apple.com" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="www.appleiphonecell.com" \
    action=allow comment="OptimumWiFi"

# Linux captive portal detection
/ip hotspot walled-garden add dst-host="connectivity-check.ubuntu.com" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="nmcheck.gnome.org" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="network-test.debian.org" \
    action=allow comment="OptimumWiFi"

# Windows captive portal detection
/ip hotspot walled-garden add dst-host="www.msftconnecttest.com" \
    action=allow comment="OptimumWiFi"
/ip hotspot walled-garden add dst-host="www.msftncsi.com" \
    action=allow comment="OptimumWiFi"

:put "  ✅ Walled garden configured for all OS"

# ── STEP 11 — Login page ──────────────────────────────────────
:put "Step 11: Setting up login page redirect..."
/file set "flash/webtune-hotspot/login.html" \
    contents=("<html><head><meta http-equiv='refresh' content='0;url=https://" . $portalDomain . "/?mac=\$(mac)&ip=\$(ip)&router=\$(identity)'></head><body>Redirecting...</body></html>")
:put "  ✅ Login page redirects to portal"

# ── STEP 12 — Command polling scheduler ───────────────────────
:put "Step 12: Setting up command polling..."
/system scheduler remove [find name="OptimumWiFiPoller"]
/system scheduler add \
    name=OptimumWiFiPoller \
    interval=2s \
    on-event=("/tool fetch url=\"https://" . $portalDomain . "/network/router/\$([ /system identity get name ])/commands/\" http-method=get output=user") \
    comment="Optimum WiFi — polls Django for commands"
:put "  ✅ Command polling every 2 seconds"

# ── STEP 13 — Register with Django ────────────────────────────
:put "Step 13: Registering with Django portal..."
:local regUrl ("https://" . $portalDomain . "/network/register-router/")
:local body ("{\"identity\":\"" . $routerIdentity . "\",\"location\":\"" . $routerLocation . "\",\"ip_address\":\"" . $wgIP . "\",\"public_key\":\"" . $pubKey . "\",\"gateway_ip\":\"" . $lanIP . "\",\"api_username\":\"admin\",\"api_password\":\"\",\"api_port\":8728,\"connection_type\":\"wireguard\"}")

:do {
    /tool fetch \
        url=$regUrl \
        http-method=post \
        http-header-field="Content-Type: application/json" \
        http-data=$body \
        output=none
    :put "  ✅ Registered with Django portal"
} on-error={
    :put "  ⚠️  Could not reach portal — check internet connection"
}

# ── DONE ──────────────────────────────────────────────────────
:put ""
:put "═══════════════════════════════════════════════"
:put "✅ CONFIGURATION COMPLETE"
:put ("   Router  : " . $routerIdentity)
:put ("   Location: " . $routerLocation)
:put ("   Tunnel  : " . $wgIP)
:put ("   Pub Key : " . $pubKey)
:put ""
:put "⚠️  NEXT STEP — Add router to VPS WireGuard:"
:put "   SSH into VPS and run:"
:put ("   wg set wg0 peer " . $pubKey . " allowed-ips " . $wgIP . "/32")
:put ""
:put "   Then test tunnel:"
:put ("   ping " . $wgIP)
:put "═══════════════════════════════════════════════"