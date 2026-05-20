# ═══════════════════════════════════════════════════════════════
# 404 Tech WiFi Portal — MikroTik Full Auto-Configuration Script
# RouterOS 7.x
# Hard reset your router, open terminal, paste this, press Enter
# That's it. Everything configures automatically.
# ═══════════════════════════════════════════════════════════════

# ── EDIT THESE VARIABLES BEFORE RUNNING ────────────────────────
:local routerIdentity   "Kampala-CBD"
:local routerLocation   "Kampala Central"
:local wgIP             "10.0.0.3"
:local djangoIP         "10.0.0.1"
:local djangoPort       "8000"
:local wgServerEndpoint "YOUR_Z440_PUBLIC_IP"
:local wgServerPort     "51820"
:local wgServerPubKey   "YOUR_Z440_WIREGUARD_PUBLIC_KEY"
:local apiPassword      ""
:local lanIP            "192.168.88.1"
:local lanNetwork       "192.168.88.0/24"
:local poolStart        "192.168.88.2"
:local poolEnd          "192.168.88.254"
# ═══════════════════════════════════════════════════════════════

:put ""
:put "═══════════════════════════════════════════════"
:put "  404 Tech WiFi Portal — Auto Configuration"
:put "═══════════════════════════════════════════════"
:put ("  Router  : " . $routerIdentity)
:put ("  Location: " . $routerLocation)
:put "═══════════════════════════════════════════════"
:put ""

# ── STEP 1 — Router identity ───────────────────────────────────
:put "Step 1: Setting router identity..."
/system identity set name=$routerIdentity
:put "  ✅ Identity: $routerIdentity"

# ── STEP 2 — Bridge ───────────────────────────────────────────
:put "Step 2: Configuring LAN bridge..."
:if ([:len [/interface bridge find name="bridge1"]] = 0) do={
    /interface bridge add name=bridge1 protocol-mode=rstp
    :put "  ✅ bridge1 created"
} else={
    :put "  ℹ️  bridge1 already exists"
}

# Add ethernet ports to bridge (ether2 to ether5)
:foreach port in={"ether2";"ether3";"ether4";"ether5"} do={
    :if ([:len [/interface bridge port find interface=$port bridge=bridge1]] = 0) do={
        :do {
            /interface bridge port add interface=$port bridge=bridge1
        } on-error={}
    }
}
:put "  ✅ Ethernet ports added to bridge"

# Add wlan1 to bridge if wireless interface exists
:if ([:len [/interface wireless find name="wlan1"]] > 0) do={
    :if ([:len [/interface bridge port find interface="wlan1" bridge=bridge1]] = 0) do={
        /interface bridge port add interface=wlan1 bridge=bridge1
    }
    :put "  ✅ wlan1 added to bridge"
}

# Set bridge IP
:if ([:len [/ip address find interface="bridge1"]] = 0) do={
    /ip address add address=($lanIP . "/24") interface=bridge1
    :put ("  ✅ LAN IP set: " . $lanIP . "/24")
} else={
    :put "  ℹ️  LAN IP already set"
}

# ── STEP 3 — DHCP Server ──────────────────────────────────────
:put "Step 3: Configuring DHCP server..."

# Create IP pool
:if ([:len [/ip pool find name="dhcp_pool0"]] = 0) do={
    /ip pool add name=dhcp_pool0 ranges=($poolStart . "-" . $poolEnd)
    :put "  ✅ DHCP pool created"
} else={
    :put "  ℹ️  DHCP pool already exists"
}

# Create DHCP server
:if ([:len [/ip dhcp-server find name="dhcp1"]] = 0) do={
    /ip dhcp-server add name=dhcp1 interface=bridge1 \
        address-pool=dhcp_pool0 lease-time=30m disabled=no
    :put "  ✅ DHCP server created"
} else={
    :put "  ℹ️  DHCP server already exists"
}

# Create DHCP network entry
:if ([:len [/ip dhcp-server network find address=$lanNetwork]] = 0) do={
    /ip dhcp-server network add address=$lanNetwork \
        gateway=$lanIP dns-server=$lanIP
    :put "  ✅ DHCP network entry created"
} else={
    :put "  ℹ️  DHCP network already exists"
}

# ── STEP 4 — WireGuard ────────────────────────────────────────
:put "Step 4: Configuring WireGuard tunnel..."

# Create WireGuard interface
:if ([:len [/interface wireguard find name="wg0"]] = 0) do={
    /interface wireguard add name=wg0 listen-port=$wgServerPort
    :put "  ✅ WireGuard interface created"
} else={
    :put "  ℹ️  WireGuard already exists"
}

# Get public key
:local pubKey [/interface wireguard get wg0 public-key]

# Set WireGuard IP
:if ([:len [/ip address find interface="wg0"]] = 0) do={
    /ip address add address=($wgIP . "/24") interface=wg0
    :put ("  ✅ Tunnel IP: " . $wgIP)
} else={
    :put "  ℹ️  Tunnel IP already set"
}

# Remove old peer and add fresh one pointing to Z440
/interface wireguard peers remove [find interface="wg0"]
/interface wireguard peers add \
    interface=wg0 \
    public-key=$wgServerPubKey \
    endpoint-address=$wgServerEndpoint \
    endpoint-port=$wgServerPort \
    allowed-address="10.0.0.0/24" \
    persistent-keepalive=25
:put "  ✅ Z440 added as WireGuard peer"

# ── STEP 5 — NAT (internet sharing) ──────────────────────────
:put "Step 5: Configuring NAT..."
:if ([:len [/ip firewall nat find chain=srcnat action=masquerade]] = 0) do={
    /ip firewall nat add chain=srcnat action=masquerade \
        out-interface=ether1 comment="Internet sharing"
    :put "  ✅ NAT masquerade added"
} else={
    :put "  ℹ️  NAT already configured"
}

# ── STEP 6 — Firewall rules ───────────────────────────────────
:put "Step 6: Configuring firewall..."

# Allow portal traffic on port 8000
:if ([:len [/ip firewall filter find comment="Allow Portal 8000"]] = 0) do={
    /ip firewall filter add \
        chain=forward action=accept protocol=tcp \
        dst-address=$djangoIP dst-port=8000 \
        comment="Allow Portal 8000"
    :put "  ✅ Portal forwarding rule added"
}

:if ([:len [/ip firewall filter find comment="Allow Portal Input"]] = 0) do={
    /ip firewall filter add \
        chain=input action=accept protocol=tcp \
        dst-port=8000 comment="Allow Portal Input"
    :put "  ✅ Portal input rule added"
}

# Allow Django API access through WireGuard
:if ([:len [/ip firewall filter find comment="Allow Django API"]] = 0) do={
    /ip firewall filter add \
        chain=input action=accept protocol=tcp \
        src-address=$djangoIP dst-port=8728 \
        comment="Allow Django API" place-before=0
    :put "  ✅ Django API firewall rule added"
}

# ── STEP 7 — RouterOS services ────────────────────────────────
:put "Step 7: Configuring services..."
/ip service set api     disabled=no  port=8728
/ip service set api-ssl disabled=yes
/ip service set telnet  disabled=yes
/ip service set ftp     disabled=yes
:put "  ✅ API enabled, telnet and FTP disabled"

# ── STEP 8 — WiFi SSID ────────────────────────────────────────
:put "Step 8: Setting WiFi name..."
:if ([:len [/interface wireless find]] > 0) do={
    /interface wireless set [find] \
        ssid="OPTIMUM HOTSPOT" \
        mode=ap-bridge \
        disabled=no
    :put "  ✅ WiFi: OPTIMUM HOTSPOT"
} else={
    :put "  ℹ️  No wireless interface — skipping"
}

# ── STEP 9 — Hotspot profile ──────────────────────────────────
:put "Step 9: Configuring hotspot profile..."
:if ([:len [/ip hotspot profile find name="hsprof1"]] = 0) do={
    /ip hotspot profile add \
        name=hsprof1 \
        hotspot-address=$lanIP \
        dns-name="hotspot.local" \
        login-by=cookie,http-chap \
        html-directory=flash/webtune-hotspot \
        http-cookie-lifetime=0s
    :put "  ✅ Hotspot profile created"
} else={
    # Update existing profile
    /ip hotspot profile set [find name="hsprof1"] \
        hotspot-address=$lanIP \
        dns-name="hotspot.local" \
        login-by=cookie,http-chap
    :put "  ℹ️  Hotspot profile updated"
}

# ── STEP 10 — Hotspot ─────────────────────────────────────────
:put "Step 10: Configuring hotspot..."
:if ([:len [/ip hotspot find name="hotspot1"]] = 0) do={
    /ip hotspot add \
        name=hotspot1 \
        interface=bridge1 \
        address-pool=dhcp_pool0 \
        profile=hsprof1 \
        idle-timeout=5m \
        disabled=no
    :put "  ✅ Hotspot created on bridge1"
} else={
    :put "  ℹ️  Hotspot already exists"
}

# ── STEP 11 — Walled garden ───────────────────────────────────
:put "Step 11: Configuring walled garden..."

# Remove old entries and add fresh ones
/ip hotspot walled-garden ip remove [find comment="404Tech"]
/ip hotspot walled-garden ip add \
    dst-address=$djangoIP action=accept comment="404Tech"
/ip hotspot walled-garden ip add \
    dst-address=$lanIP action=accept comment="404Tech"

:put ("  ✅ Walled garden: " . $djangoIP . " and " . $lanIP)

# ── STEP 12 — DNS ─────────────────────────────────────────────
:put "Step 12: Configuring DNS..."
/ip dns static remove [find name="hotspot.local" type=A]
/ip dns static add name="hotspot.local" address=$djangoIP
:put ("  ✅ hotspot.local → " . $djangoIP)

# ── STEP 13 — Register with Django ────────────────────────────
:put "Step 13: Registering with Django portal..."

:local regUrl ("http://" . $djangoIP . ":" . $djangoPort . "/network/register-router/")
:local body ("{\"identity\":\"" . $routerIdentity . "\",\"location\":\"" . $routerLocation . "\",\"ip_address\":\"" . $wgIP . "\",\"public_key\":\"" . $pubKey . "\",\"gateway_ip\":\"" . $lanIP . "\",\"api_username\":\"admin\",\"api_password\":\"" . $apiPassword . "\",\"api_port\":8728,\"connection_type\":\"wireguard\"}")

:do {
    /tool fetch \
        url=$regUrl \
        http-method=post \
        http-header-field="Content-Type: application/json" \
        http-data=$body \
        output=none
    :put "  ✅ Registered with Django"
} on-error={
    :put "  ⚠️  Django not reachable yet — WireGuard tunnel not active"
    :put "  ℹ️  Add public key to Z440 then run Step 13 again"
}

# ── DONE ──────────────────────────────────────────────────────
:put ""
:put "═══════════════════════════════════════════════"
:put "✅ CONFIGURATION COMPLETE"
:put ("   Router   : " . $routerIdentity)
:put ("   Location : " . $routerLocation)
:put ("   Tunnel IP: " . $wgIP)
:put ("   Pub Key  : " . $pubKey)
:put ""
:put "⚠️  NEXT STEP — Add this public key to Z440:"
:put ("   " . $pubKey)
:put ""
:put "   Once added the tunnel activates and Django"
:put "   can control this router remotely."
:put "═══════════════════════════════════════════════"