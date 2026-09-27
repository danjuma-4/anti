#!/bin/bash
# /root/anti/entrypoint.sh

# 1. Cleanup residual GMS data to prevent identity leakage
rm -rf /data/data/com.google.android.gms/files/*
rm -rf /data/data/com.google.android.gsf/files/*

# 2. Identity Generation
/root/anti/scripts/01-identity.sh

# 3. Fingerprint Rotation
VERSIONS=("10" "11" "12")
SELECTED=${VERSIONS[$RANDOM % ${#VERSIONS[@]}]}
/root/anti/scripts/03-fingerprint.sh $SELECTED

# 4. Proxy Configuration (02-proxy.sh)
# Assuming 02-proxy.sh handles the egress routing
/root/anti/scripts/02-proxy.sh

# 5. Start the Android Zygote/Init
# This assumes the base image's init is at /init
exec /init
