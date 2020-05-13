FROM openjdk:8-jdk-stretch as builder
LABEL maintainer="cgiraldo@gradiant.org"
LABEL organization="gradiant.org"

ARG VERSION=2.4.0
ENV VERSION=$VERSION

RUN echo 'deb http://deb.debian.org/debian stretch main' >> /etc/apt/sources.list && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        apt-transport-https \
        autoconf \
        automake \
        build-essential \
        curl \
        git \
        gnuplot \
        openjdk-8-jdk \
        python \
        wget \
        unzip \
        && \
    rm -rf /var/lib/apt/lists/*

# building opentsdb

RUN wget -qO- https://github.com/OpenTSDB/opentsdb/archive/v$VERSION.tar.gz | tar xvz -C /opt
RUN ln -s /opt/opentsdb-$VERSION /opt/opentsdb
RUN find /opt/opentsdb/ -type f -exec sed -i 's#http://[^.]\+\.maven\.org#https://repo1.maven.org#g' {} \+ \
    && \
    cd /opt/opentsdb && ./build.sh

RUN mkdir -p /opt/opentsdb/dist/usr/share/opentsdb/bin && \
    mkdir -p /opt/opentsdb/dist/usr/share/opentsdb/lib && \
    mkdir -p /opt/opentsdb/dist/usr/share/opentsdb/plugins && \
    mkdir -p /opt/opentsdb/dist/usr/share/opentsdb/static && \
    mkdir -p /opt/opentsdb/dist/usr/share/opentsdb/tools && \
    mkdir -p /opt/opentsdb/dist/etc/opentsdb && \
    mkdir -p /var/log/opentsdb
RUN cd /opt/opentsdb-$VERSION && \
    cp src/opentsdb.conf /opt/opentsdb/dist/etc/opentsdb/ && \
    cp src/logback.xml /opt/opentsdb/dist/etc/opentsdb/ && \
    cp src/mygnuplot.sh /opt/opentsdb/dist/usr/share/opentsdb/bin && \
    cp build/tsdb-$VERSION.jar /opt/opentsdb/dist/usr/share/opentsdb/lib && \
    cp build/tsdb /opt/opentsdb/dist/usr/share/opentsdb/bin/ && \
    cp build/third_party/*/*.jar /opt/opentsdb/dist/usr/share/opentsdb/lib/ && \
    cp -rL build/staticroot/* /opt/opentsdb/dist/usr/share/opentsdb/static
RUN sed -i "s@pkgdatadir=''@pkgdatadir='/usr/share/opentsdb'@g" /opt/opentsdb/dist/usr/share/opentsdb/bin/tsdb
RUN sed -i "s@configdir=''@configdir='/etc/opentsdb'@g" /opt/opentsdb/dist/usr/share/opentsdb/bin/tsdb
# Set Configuration Defaults
RUN sed -i "s@tsd.network.port =.*@tsd.network.port = 4242@g" /opt/opentsdb/dist/etc/opentsdb/opentsdb.conf
RUN sed -i "s@tsd.http.staticroot =.*@tsd.http.staticroot = /usr/share/opentsdb/static/@g" /opt/opentsdb/dist/etc/opentsdb/opentsdb.conf
RUN sed -i "s@tsd.http.cachedir =.*@tsd.http.cachedir = /tmp/opentsdb@g" /opt/opentsdb/dist/etc/opentsdb/opentsdb.conf
RUN sed -i '/CORE.*/a # Full path to a directory containing plugins for OpenTSDB\ntsd.core.plugin_path = /usr/share/opentsdb/plugins/' /opt/opentsdb/dist/etc/opentsdb/opentsdb.conf 

FROM openjdk:8-jre-slim

LABEL maintainer="cgiraldo@gradiant.org" \
      organization="gradiant.org"

ENV OPENTSDB_VERSION=2.4.0 \
    OPENTSDB_PREFIX=/usr/share/opentsdb \
    LOGDIR=/var/log/opentsdb \
    PATH=$PATH:/usr/share/opentsdb/bin
# It is expected these might need to be passed in with the -e flag
ARG       JAVA_OPTS="-Xms512m -Xmx2048m"

WORKDIR   $OPENTSDB_PREFIX

COPY --from=builder /opt/opentsdb/dist /

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    curl \
    dnsutils \
    gnuplot \
    net-tools \
    procps \
    sed \
    wget \
    && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/log/opentsdb && \
    useradd --comment "OpenTSDB" -u 202 --shell /bin/bash -M -r --home /opt/opentsdb/ opentsdb && \
    # fix dns issues with java, especially with short living containers
    # 30s is generally recommended, lower values will just stress dns more, while higher values
    # just tend to keep stale entries for too long
    sed -i 's/.*networkaddress.cache.ttl.*/networkaddress.cache.ttl=30/g' /usr/local/openjdk-8/lib/security/java.security
    # networkaddress.cache.negative.ttl=10 which is default

COPY entrypoint.sh /entrypoint.sh

RUN chown -R opentsdb:opentsdb /var/log/opentsdb

USER opentsdb:opentsdb

ENTRYPOINT ["/entrypoint.sh"]

