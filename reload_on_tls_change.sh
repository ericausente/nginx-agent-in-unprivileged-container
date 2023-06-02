#!/bin/bash

# wait for the nginx process to "initially" read the files first
sleep 10

while true; do
    # calm down for 10 seconds if nginx is reloaded
    /usr/bin/inotifywait --timefmt '%H:%M:%S' --format '%T %w %e' /etc/nginx/ssl/* && nginx -t && nginx -s reload && echo "NGINX reloaded." && sleep 10
done
