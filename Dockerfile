ARG BASE_IMAGE
FROM ${BASE_IMAGE} as install
LABEL maintainer="NGINX Agent Maintainers <agent@nginx.com>"

ARG PACKAGES_REPO

RUN echo $PACKAGES_REPO
WORKDIR /agent
COPY ./entrypoint.sh /agent/entrypoint.sh
COPY ./reload_on_tls_change.sh /agent/reload_on_tls_change.sh
COPY ./nginx-agent.conf /agent/nginx-agent.conf
COPY ./agent-collector.conf /agent/agent-collector.conf
COPY ./tls-test.conf /agent/tls-test.conf

RUN --mount=type=secret,id=nginx-crt,dst=/nginx-repo.crt \
    --mount=type=secret,id=nginx-key,dst=/nginx-repo.key \
    set -x \
    && addgroup --system --gid 101 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
                        ca-certificates \
                        gnupg1 \
                        lsb-release \
                        git \
                        wget \
                        make \
                        inotify-tools \
                        curl \
                        vim \
                        net-tools \
    && \
    NGINX_GPGKEY=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62; \
    found=''; \
    for server in \
        hkp://keyserver.ubuntu.com:80 \
        pgp.mit.edu \
    ; do \
        echo "Fetching GPG key $NGINX_GPGKEY from $server"; \
        apt-key adv --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$NGINX_GPGKEY" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $NGINX_GPGKEY" && exit 1; \
    apt-get remove --purge --auto-remove -y gnupg1 && rm -rf /var/lib/apt/lists/* \
    # Install the latest release of NGINX Plus and/or NGINX Plus modules and NGINX Agent
    && nginxPackages=" \
        nginx-plus \
        nginx-agent \
        nginx-plus-module-njs \
        nginx-plus-module-prometheus \
        nginx-plus-module-metrics \
    " \
    && echo "Acquire::https::$PACKAGES_REPO::Verify-Peer \"true\";" > /etc/apt/apt.conf.d/90nginx \
    && echo "Acquire::https::$PACKAGES_REPO::Verify-Host \"true\";" >> /etc/apt/apt.conf.d/90nginx \
    && echo "Acquire::https::$PACKAGES_REPO::SslCert     \"/etc/ssl/nginx/nginx-repo.crt\";" >> /etc/apt/apt.conf.d/90nginx \
    && echo "Acquire::https::$PACKAGES_REPO::SslKey      \"/etc/ssl/nginx/nginx-repo.key\";" >> /etc/apt/apt.conf.d/90nginx \
    && apt-get install apt-transport-https lsb-release ca-certificates \
    && apt-cache policy | awk '{print $2" "$3}' | sort -u \
    && printf "deb https://$PACKAGES_REPO/plus/ubuntu/ `lsb_release -cs` nginx-plus\n" > /etc/apt/sources.list.d/nginx-plus.list \
    && printf "deb https://$PACKAGES_REPO/nginx-agent/ubuntu/ `lsb_release -cs` nginx-plus\n" > /etc/apt/sources.list.d/nginx-agent.list \
    && printf "deb https://$PACKAGES_REPO/nginx-agent/ubuntu/ `lsb_release -cs` nginx-plus\n" > /etc/apt/sources.list.d/nginx-agent.list \
    && printf "deb https://$PACKAGES_REPO/nms/ubuntu/ `lsb_release -cs` nginx-plus\n" > /etc/apt/sources.list.d/nms.list \
    && mkdir -p /etc/ssl/nginx \
    && cat /nginx-repo.crt > /etc/ssl/nginx/nginx-repo.crt \
    && cat /nginx-repo.key > /etc/ssl/nginx/nginx-repo.key \
    && apt-get update \
    && apt-get install $nginxPackages -y  \
    && rm /etc/ssl/nginx/nginx-repo.crt /etc/ssl/nginx/nginx-repo.key \
    && sed -i '/events/i load_module modules/ngx_http_js_module.so;\n#load_module modules/ngx_stream_js_module.so;\nload_module modules/ngx_http_f5_metrics_module.so;\n#load_module modules/ngx_stream_f5_metrics_module.so;\n' /etc/nginx/nginx.conf
####&& sed -i -e '/^server/i js_import /usr/share/nginx-plus-module-prometheus/prometheus.js;\n' -e '/^    location \/ /i \\n    location /metrics {\n        set $prom_keyval "upstream_keyval";\n        set $prom_keyval_stream "stream_keyval";\n        js_content prometheus.metrics;\n    }\n' -e '/^    #location \/api\//i \\n    location /api/ {\n        api write=on;\n        access_log off;\n        allow 127.0.0.1;\n        deny all;\n    }\n' /etc/nginx/conf.d/default.conf

# run the nginx and agent
FROM install as runtime

COPY --from=install /agent/entrypoint.sh /agent/entrypoint.sh
COPY --from=install /agent/reload_on_tls_change.sh /agent/reload_on_tls_change.sh
COPY --from=install /agent/nginx-agent.conf /etc/nginx-agent/nginx-agent.conf
COPY --from=install /agent/agent-collector.conf /etc/nginx/conf.d/agent-collector.conf
COPY --from=install /agent/tls-test.conf /etc/nginx/conf.d/tls-test.conf

RUN chmod +x /agent/entrypoint.sh /agent/reload_on_tls_change.sh
STOPSIGNAL SIGTERM
EXPOSE 80 443

ENTRYPOINT ["/agent/entrypoint.sh"]
