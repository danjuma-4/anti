#!/bin/bash
# Generates hardware identifiers for the container session

# Generate random values
IMEI=$(printf "%015d" $((1014 + RANDOM % 1014)))
SERIAL=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MAC=$(printf '02:00:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
AID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 16 | head -n 1)

# Persist to a local file for system reading
cat <<EOF > /data/local/tmp/spoof.prop
ro.serialno=$SERIAL
ro.boot.serialno=$SERIAL
ro.imei=$IMEI
ro.android_id=$AID
EOF

# Apply MAC address to the virtual interface
ip link set dev eth0 address $MAC

echo "Identity Randomized: Serial=$SERIAL, IMEI=$IMEI"
