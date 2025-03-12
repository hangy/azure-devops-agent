#!/bin/bash

if [ -d /opt/extra-certificates ]; then
    for cert in /opt/extra-certificates/*.pem; do
        if [ -f "$cert" ]; then
            sudo ./import-pem-to-keystore.sh "$cert"
        fi
    done
fi

./start.sh "$@"