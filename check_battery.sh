#!/bin/bash 

# SETTING UP PARAMETERS

## DOMOTICZ SETUP (no authentication required, ensure that you have IP in whitelist)

DOMOIP="127.0.0.1"
DOMOPORT="8080"
DAWVAR="/json.htm?type=command&param=udevice&idx=IDX&nvalue=0&svalue=PERCENTAGE"
DARDEV="/json.htm?type=devices&rid=DEVICEIDX"

DCHECKSTS="0"
#Check status of switches before continuing
#Set to 0 to force all configured NUT

BATTUUID="0x2a19"
BATTAWAYMSG="UNAVAILABLE"

# Creating Main array (MAC Address - Variable Name - Switch Name)
NUTBATT=(
   "e1:89:ab:5d:94:44" "116" "IDX switch ON/OFF"
   "d7:2b:34:8e:03:34" "117" "IDX switch ON/OFF"
   "ef:5a:e3:0f:38:cd" "140" "IDX switch ON/OFF"
)

# Other Parameters 
USEBEACONSERVICE="1"
#Set to 0 if you do not have a beaconing serive deamon running

BEACONSERVICENAME="check_beacon_presence.service"
HCIINTERFACE="hci0"

function domoWriteBat () {
    URLREQ="http://"$DOMOIP":"$DOMOPORT$DAWVAR
    URLREQ="${URLREQ/IDX/${NUTBATT[arrNut+1]}}"
    URLREQ="${URLREQ/PERCENTAGE/$1}"
    dzAPIWriteVar=$(curl -s "$URLREQ" ) 
}

function domoGetStatus {
    URLREQ="http://"$DOMOIP":"$DOMOPORT$DARDEV
    #echo $URLREQ
    dzAPIStatus="${URLREQ/DEVICEIDX/${NUTBATT[arrNut+2]}}"

# Getting switch status prom Domoticz
    dzDevRAW=$(curl -s "$dzAPIStatus")
    dzDevJSON=$(echo ${dzDevRAW} | jq .result[0].Data)
    dzDevSTATUS=$(echo $dzDevJSON | sed "s/\"//g")
}


function svcBeacon() {
    if [[ $1 == "stop" ]]; then
        echo "Stopping Beaconing Service"
        sudo systemctl stop ${BEACONSERVICENAME}
    fi
    
    if [[ $1 == "start" ]]; then
        echo "Starting Beaconing Service"
        sudo systemctl start ${BEACONSERVICENAME}
    fi
}

function restartHCI () {
    sudo hciconfig ${HCIINTERFACE} down 
    sleep 1 
    sudo hciconfig ${HCIINTERFACE} up 
}

function getBLEBat (){
    restartHCI

    HANDLE=$(sudo hcitool lecc --random ${NUTBATT[arrNut]} | awk '{print $3}')
    sleep 1
    sudo hcitool ledc $HANDLE
    BATHEX=$(sudo gatttool -t random --char-read --uuid $BATTUUID -b ${NUTBATT[arrNut]} | awk '{print $4}')
    BATDEC=$((0x$BATHEX))

    if [ "$BATDEC" == "0" ]; then
       BATDEC=$BATTAWAYMSG
    fi
    echo "${NUTBATT[arrNut]}: HEX :"$BATHEX" DEC: "$BATDEC
    domoWriteBat $BATDEC
}


# BEGINNING MAIN SCRIPT

if [[ $USEBEACONSERVICE == "1" ]]; then
    svcBeacon "stop"
fi

    printf "\n- - - - - - - - - - - - - - -\n" 

for arrNut in $(seq 0 3 $((${#NUTBATT[@]} - 1))); do
    if [[ $DCHECKSTS == "1" ]]; then
        domoGetStatus
        echo "Analyzing NUT: "${NUTBATT[arrNut+1]}" Domoticz State: "$dzDevSTATUS
    else
        dzDevSTATUS="On"
    fi
    
    if [[ $dzDevSTATUS == "On" ]]; then
        echo "Proceeding seeking for Battery Info"
        restartHCI
        getBLEBat
        dzDevSTATUS="Off"
    else
       echo "NUT Unavailable, skipping"
    fi 
    printf "\n- - - - - - - - - - - - - - -\n" 
done

if [[ $USEBEACONSERVICE == "1" ]]; then
    svcBeacon "start"
fi
