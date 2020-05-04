#!/bin/sh
#set -x
#shellcheck disable=SC2039
#shellcheck disable=SC2143
SERVERSPATH="$0"".servers"

#check if serverlist file exists and use it
[ -f "$SERVERSPATH" ] && source "$SERVERSPATH" || printf "#List separated by commas\nSERVERLIST=\"gb,us,jp\"\n" > "$SERVERSPATH"

if [ -z "$1" ] && [ -z "$2" ]; then
     echo "Missing Args"
     echo "Syntax: AirVPN arg clientnumber"
     echo "Args: toggle (1-5), status (1-5), random (1-5), set (1-5) (Country-Code ALPHA-2 ISO3166)[entry-ip]"
     echo "Example: AirVPN set 2 gb3"
     exit 1
elif [ -n "$1" ] && [ -z "$2" ]; then
     echo "Missing VPN Client number"
     exit 1
elif [ "$2" -lt 1 ] || [ "$2" -gt 5 ]; then
     echo "VPN Client number must be between [1-5]"
     exit 1
elif [ "$1" = "set" ] && [ -z "$3" ]; then
     echo "Missing ALPHA-2 ISO3166 country code for manually setting"
     exit 1
else
     ARG="$1"
     VPN="$2"
     CURRENTSERVER="$(nvram get vpn_client"$VPN"_addr)"
     CURRENTDESC="$(nvram get vpn_client"$VPN"_desc)"
     SRV="$(echo "$3" | tr 'A-Z a-z' | sed -e 's/[0-9]//g')"
     if [ "$(echo "$CURRENTSERVER" | grep -o -E '[0-9]+')" ] && [ "$ARG" != "status" ] && [ "$ARG" != "toggle" ]; then
          ENTRY="$(echo "$CURRENTSERVER" | grep -o -E '[0-9]+')"
          echo "$CURRENTDESC: Forcing entry-ip $ENTRY to avoid connecting issues"
     else
          ENTRY="$(echo "$3" | grep -o -E '[0-9]+')"
     fi
fi

if [ "$ARG" = "set" ] && [ "$(ping -c 1 "$SRV$ENTRY".vpn.airdns.org >/dev/null 2>&1 ; echo $?)" != "0" ]; then
     echo "$CURRENTDESC: Bad address... Using random from list"
     SRV="BADADDR"
fi

#remove current server from serverlist
SERVERLIST="$(echo "$SERVERLIST" | sed -e "s/""$(echo "$CURRENTSERVER" | cut -d. -f1 | sed -e "s/[0-9]//g")""//g" -e "s/,,/,/g" -e "s/^,//g" -e "s/,$//g")"

if [[ "$ARG" = "set" || "$ARG" = "random" ]] && [[ -z "$SRV" || "$SRV" = "BADADDR" ]]; then
     NEWSERVER="$(echo "$SERVERLIST" | cut -d "," -f"$(awk -v min=1 -v max="$(echo "$SERVERLIST" | sed "s/,/ /g" | wc -w)" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')")$ENTRY.vpn.airdns.org"
else
     NEWSERVER="$SRV$ENTRY.vpn.airdns.org"
fi

if [ "$ARG" = "toggle" ]; then
    if [ -f "/etc/openvpn/client$VPN/status" ]; then
        service stop_vpnclient"$VPN" >/dev/null 2>&1
        echo "$CURRENTDESC: OFF ($CURRENTSERVER)"
    else
        service start_vpnclient"$VPN" >/dev/null 2>&1
        echo "$CURRENTDESC: ON ($CURRENTSERVER) ($(ping -c 5 "$CURRENTSERVER" | tail -1 | awk '{print $4}' | cut -d '/' -f 2) ms)"
    fi
elif [ "$ARG" = "status" ]; then
     if [ -f "/etc/openvpn/client$VPN/status" ]; then
        echo "$CURRENTDESC: ON ($CURRENTSERVER) ($(ping -c 5 "$CURRENTSERVER" | tail -1 | awk '{print $4}' | cut -d '/' -f 2) ms)"
     else
        echo "$CURRENTDESC: OFF ($CURRENTSERVER)"
     fi
elif [ "$ARG" = "random" ] || [ "$ARG" = "set" ]; then
     if [ "$NEWSERVER" = "$CURRENTSERVER" ]; then
          echo "$CURRENTDESC: New server is the same as current server, ignoring..."
     else
          echo "$CURRENTDESC: Changing server to $NEWSERVER ($(ping -c 5 "$NEWSERVER" | tail -1 | awk '{print $4}' | cut -d '/' -f 2) ms)" 
          nvram set vpn_client"$VPN"_addr="$NEWSERVER" >/dev/null 2>&1
          nvram commit >/dev/null 2>&1
          if [ -f "/etc/openvpn/client$VPN/status" ]; then
               service restart_vpnclient"$VPN" >/dev/null 2>&1
          fi
     fi
else
    echo "Error! Bad arguments..."
    exec "${0}"
fi
