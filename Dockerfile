FROM java:8
MAINTAINER Chuan Liu <liuchuan@liuchuan.org>

# Presto
ENV PRESTO_HOME /usr/local/presto
ENV PRESTO_CONFIG_HOME $PRESTO_HOME/etc
ENV PRESTO_CATALOG_HOME $PRESTO_HOME/etc/catalog

RUN mkdir -p $PRESTO_HOME $PRESTO_CONFIG_HOME
WORKDIR $PRESTO_HOME

ENV PRESTO_VERSION 0.150
ENV PRESTO_TGZ_URL https://repo1.maven.org/maven2/com/facebook/presto/presto-server/$PRESTO_VERSION/presto-server-$PRESTO_VERSION.tar.gz
ENV PRESTO_TGZ_SHA1_URL $PRESTO_TGZ_URL.sha1

RUN set -x \
        && PRESTO_TGZ_SHA1=$(curl -fsSL $PRESTO_TGZ_SHA1_URL) \
        && curl -fsSL "$PRESTO_TGZ_URL" -o presto.tar.gz \
        && echo "$PRESTO_TGZ_SHA1 presto.tar.gz" | sha1sum -c - \
        && tar -xvf presto.tar.gz --strip-components=1 \
        && rm presto.tar.gz*

COPY config/node.properties $PRESTO_CONFIG_HOME/
COPY config/config.properties $PRESTO_CONFIG_HOME/
COPY config/jvm.config $PRESTO_CONFIG_HOME/
COPY config/log.properties $PRESTO_CONFIG_HOME/

COPY config/jmx.properties $PRESTO_CATALOG_HOME/

# Airpal
ENV AIRPAL_COMMIT 550ad14a589a41c95a7a82d14560f3995c419188
ENV AIRPAL_HOME /opt/airpal

RUN set -x \
  && apt-get update && apt-get install -y make g++ \
  && export BUILD_DIR=$(mktemp -d) && cd "${BUILD_DIR}" \
  && git clone https://github.com/airbnb/airpal \
  && cd airpal && git checkout "${AIRPAL_COMMIT}" \
  && ./gradlew clean shadowJar \
  && mkdir -p ${AIRPAL_HOME} \
  && cp build/libs/airpal-*-all.jar $AIRPAL_HOME \
  && cd "${HOME}" && rm -rf .npm .gradle .node-gyp \
  && rm -rf "${BUILD_DIR}" \
  && apt-get purge --auto-remove -y make g++ \
  && apt-get clean

ADD config/reference.h2.yml $AIRPAL_HOME/reference.yml
ADD airpal_launcher.sh $AIRPAL_HOME/launcher

RUN set -x \
  && java -Duser.timezone=UTC -cp ${AIRPAL_HOME}/airpal-*-all.jar \
  com.airbnb.airpal.AirpalApplication db migrate ${AIRPAL_HOME}/reference.yml

# Add hadoop-azure to allow querying data in Azure storage
# as a workaround for the following PR (before it can be merged):
#   https://github.com/prestodb/presto-hadoop-apache2/pull/14
ENV HADOOP_AZURE_URL http://repo1.maven.org/maven2/org/apache/hadoop/hadoop-azure/2.7.2/hadoop-azure-2.7.2.jar
ENV AZURE_STORAGE_URL http://repo1.maven.org/maven2/com/microsoft/azure/azure-storage/2.2.0/azure-storage-2.2.0.jar
ENV COMMONS_LANG_URL http://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar
ENV JETTY_UTIL_URL http://repo1.maven.org/maven2/org/mortbay/jetty/jetty-util/6.1.26/jetty-util-6.1.26.jar

ENV HIVE_HADOOP2_HOME $PRESTO_HOME/plugin/hive-hadoop2

RUN set -x \
    && wget -P "${HIVE_HADOOP2_HOME}" "${HADOOP_AZURE_URL}" \
    && wget -P "${HIVE_HADOOP2_HOME}" "${AZURE_STORAGE_URL}" \
    && wget -P "${HIVE_HADOOP2_HOME}" "${COMMONS_LANG_URL}" \
    && wget -P "${HIVE_HADOOP2_HOME}" "${JETTY_UTIL_URL}"



# Supervisor
RUN apt-get install -y supervisor
RUN mkdir -p /var/log/supervisor
ADD config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8080 8081 8082
CMD ["/usr/bin/supervisord"]

