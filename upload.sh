#!/bin/sh

IP=""
BAUD=9600
DEV=/dev/ttyUSB0

[ -e ./local.sh ] && . ./local.sh

check_timestamp ()
{
    if [ ! -e $TS ] || [ "$1" -nt $TS ]; then
        true
    else
        false
    fi
}

upload_script ()
{
    SCRIPT="$1"
    shift
    echo "Checking $SCRIPT"
    if [ ! -e "$SCRIPT" ]; then
        return
    fi
    
    if check_timestamp "$SCRIPT"; then
        echo "Running '$LUATOOL -f $SCRIPT $@'"
        $LUATOOL -f "$SCRIPT" $@
        [ $? -ne 0 ] && exit 1
    fi
}

OPT=""
if [ ! -z "$IP" ] && ping -q -c1 -W3 "$IP" > /dev/null; then
    MAC=`arp -n -a | grep "$IP" | awk '{ print $4 }'`
    if echo "$MAC" | grep -q '^ac:d0:74\|^5c:cf:7f\|^18:fe:34'; then
        echo "Found ESP8266 with MAC address $MAC at $IP"
        if nc -z $IP 23; then
            echo "Using telnet connection"
            OPT="--ip $IP"
        else
            echo "Telnet not running, falling back to serial"
        fi
    else
        echo "$IP is not an Espressif device"
    fi
else
    [ ! -z "$IP" ] && echo "$IP is down"
fi
LUATOOL="luatool.py -p $DEV -b $BAUD $OPT"

TS=.timestamp
#[ ! -e $TS ] && touch $TS

upload_script init_real.lua -c
upload_script mpd.lua -c
upload_script remote.lua -c
upload_script network.lua -c
if [ -r local.lua ]; then
    if ! (check_timestamp local.lua && check_timestamp init.lua); then
        echo "Creating localized init.lua"
        cat local.lua init.lua > .init.tmp
        upload_script .init.tmp -t init.lua
    fi
else
    upload_script init.lua
fi

touch $TS

echo "Restarting"
$LUATOOL -n

screen $DEV $BAUD
if [ $? -eq 0 ]; then
    exit 0
fi

for i in seq 5; do
    if nc -z $IP 23; then
        telnet $IP
        break
    fi
done
