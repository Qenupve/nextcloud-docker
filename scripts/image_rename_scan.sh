#!/bin/bash

# wait for image_rename.sh instances to do their work and populate /tmp/to_scan.txt
sleep 10

if [ -e "/tmp/to_scan.txt" ]; then
    for LINE in "$(cat /tmp/to_scan.txt | sort -u)"; do
        echo "scanning $LINE"
        php /var/www/html/occ files:scan --path="$LINE" --shallow
    done
    rm /tmp/to_scan.txt
fi