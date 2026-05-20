# ═══════════════════════════════════════════════════════════════
# optimum wifi — MikroTik Command Poller
# Runs every 5 seconds via scheduler
# Polls Django for pending commands and executes them
# ═══════════════════════════════════════════════════════════════

:local djangoURL "https://optimuminnovationhotspot.com/network/router/ROUTER_ID/commands/"
:local confirmURL "https://optimuminnovationhotspot.com/network/command/"

# ── Fetch pending commands from Django ────────────────────────
:local result
:do {
    :set result [/tool fetch \
        url=$djangoURL \
        http-method=get \
        output=user \
        as-value]
} on-error={
    :log error "WiFi Portal: Could not reach Django server"
    :quit
}

:local body ($result->"data")

# ── Parse and execute each command ────────────────────────────
# Django returns JSON array of commands
# We parse command_id, action, mac_address

:local lines [:toarray $body]

:foreach line in=$lines do={

    # Extract command fields
    :local cmdId     ""
    :local action    ""
    :local mac       ""
    :local ip        ""
    :local success   true
    :local errMsg    ""

    # Simple JSON field extraction
    :if ([:find $line "\"action\": \"grant\""] >= 0) do={
        :set action "grant"
    }
    :if ([:find $line "\"action\": \"revoke\""] >= 0) do={
        :set action "revoke"
    }
    :if ([:find $line "\"action\": \"block\""] >= 0) do={
        :set action "block"
    }
    :if ([:find $line "\"action\": \"unblock\""] >= 0) do={
        :set action "unblock"
    }

    # Extract command ID
    :if ([:find $line "\"id\":"] >= 0) do={
        :local idStart ([:find $line "\"id\": "] + 6)
        :local idEnd   [:find $line "," $idStart]
        :set cmdId [:pick $line $idStart $idEnd]
        :set cmdId [:tostr $cmdId]
    }

    # Extract MAC address
    :if ([:find $line "\"mac_address\":"] >= 0) do={
        :local macStart ([:find $line "\"mac_address\": \""] + 16)
        :local macEnd   [:find $line "\"" $macStart]
        :set mac [:pick $line $macStart $macEnd]
    }

    # Extract IP address
    :if ([:find $line "\"ip_address\":"] >= 0) do={
        :local ipStart ([:find $line "\"ip_address\": \""] + 15)
        :local ipEnd   [:find $line "\"" $ipStart]
        :set ip [:pick $line $ipStart $ipEnd]
    }

    # ── Execute command ────────────────────────────────
    :if ($action = "grant" && $mac != "") do={
        :do {
            # Remove any existing binding first
            :local existing [/ip hotspot ip-binding find mac-address=$mac]
            :if ([:len $existing] > 0) do={
                /ip hotspot ip-binding remove $existing
            }
            # Add bypassed binding
            /ip hotspot ip-binding add \
                mac-address=$mac \
                type=bypassed \
                comment=("WiFi_Portal_" . $mac)
            :log info ("WiFi Portal: Granted internet to " . $mac)
        } on-error={
            :set success false
            :set errMsg "Failed to grant internet"
            :log error ("WiFi Portal: Failed to grant internet to " . $mac)
        }
    }

    :if ($action = "revoke" && $mac != "") do={
        :do {
            :local existing [/ip hotspot ip-binding find mac-address=$mac]
            :if ([:len $existing] > 0) do={
                /ip hotspot ip-binding remove $existing
            }
            # Remove from active sessions too
            :local active [/ip hotspot active find mac-address=$mac]
            :if ([:len $active] > 0) do={
                /ip hotspot active remove $active
            }
            :log info ("WiFi Portal: Revoked internet from " . $mac)
        } on-error={
            :set success false
            :set errMsg "Failed to revoke internet"
        }
    }

    :if ($action = "block" && $mac != "") do={
        :do {
            :local existing [/ip hotspot ip-binding find mac-address=$mac]
            :if ([:len $existing] > 0) do={
                /ip hotspot ip-binding set $existing type=blocked
            } else={
                /ip hotspot ip-binding add \
                    mac-address=$mac \
                    type=blocked \
                    comment=("WiFi_Portal_Blocked_" . $mac)
            }
            :log info ("WiFi Portal: Blocked " . $mac)
        } on-error={
            :set success false
            :set errMsg "Failed to block device"
        }
    }

    :if ($action = "unblock" && $mac != "") do={
        :do {
            :local existing [/ip hotspot ip-binding find mac-address=$mac type=blocked]
            :if ([:len $existing] > 0) do={
                /ip hotspot ip-binding remove $existing
            }
            :log info ("WiFi Portal: Unblocked " . $mac)
        } on-error={
            :set success false
            :set errMsg "Failed to unblock device"
        }
    }

    # ── Confirm execution back to Django ──────────────
    :if ($cmdId != "") do={
        :local confirmBody ""
        :if ($success) do={
            :set confirmBody "{\"success\": true}"
        } else={
            :set confirmBody ("{\"success\": false, \"error\": \"" . $errMsg . "\"}")
        }

        :do {
            /tool fetch \
                url=($confirmURL . $cmdId . "/confirm/") \
                http-method=post \
                http-header-field="Content-Type: application/json" \
                http-data=$confirmBody \
                output=none
        } on-error={
            :log error "WiFi Portal: Could not confirm command"
        }
    }
}