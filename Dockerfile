FROM ubuntu:xenial
LABEL MAINTAINER="Woohyeok Choi <woohyeok.choi@kaist.ac.kr>"

RUN apt-get update \
    && apt-get install -y python python-pip curl

RUN curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --skip-server --skip-tools \
    && apt-get install -y maxscale mariadb-client

RUN pip2 install --no-cache-dir crudini

RUN rm -rf /var/lib/apt/lists/* \
    && mkdir -p /scripts/ \
    && mkdir -p /etc/maxscale/ \
    && mkdir -p /var/log/maxscale/

RUN ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

COPY ./docker-entrypoint.sh /scripts/docker-entrypoint.sh

EXPOSE 3306

VOLUME [ "/var/log/maxscale/" ]

CMD [ "/bin/bash", "/scripts/docker-entrypoint.sh" ]