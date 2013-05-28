#!/bin/sh

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

usage() {
  echo "
usage: $0 <options>
  Required not-so-options:
     --distro-dir=DIR            path to distro specific files (debian/RPM)
     --build-dir=DIR             path to dist dir
     --prefix=PREFIX             path to install into

  Optional options:
     --doc-dir=DIR               path to install docs into [/usr/share/doc/solr]
     --lib-dir=DIR               path to install bits [/usr/lib/solr]
     --installed-lib-dir=DIR     path where lib-dir will end up on target system
     --bin-dir=DIR               path to install bins [/usr/bin]
     --examples-dir=DIR          path to install examples [doc-dir/examples]
     ... [ see source for more similar options ]
  "
  exit 1
}

OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'prefix:' \
  -l 'distro-dir:' \
  -l 'doc-dir:' \
  -l 'lib-dir:' \
  -l 'installed-lib-dir:' \
  -l 'bin-dir:' \
  -l 'examples-dir:' \
  -l 'build-dir:' -- "$@")

if [ $? != 0 ] ; then
    usage
fi

eval set -- "$OPTS"
while true ; do
    case "$1" in
        --prefix)
        PREFIX=$2 ; shift 2
        ;;
        --distro-dir)
        DISTRO_DIR=$2 ; shift 2
        ;;
        --build-dir)
        BUILD_DIR=$2 ; shift 2
        ;;
        --doc-dir)
        DOC_DIR=$2 ; shift 2
        ;;
        --lib-dir)
        LIB_DIR=$2 ; shift 2
        ;;
        --installed-lib-dir)
        INSTALLED_LIB_DIR=$2 ; shift 2
        ;;
        --bin-dir)
        BIN_DIR=$2 ; shift 2
        ;;
        --examples-dir)
        EXAMPLES_DIR=$2 ; shift 2
        ;;
        --)
        shift ; break
        ;;
        *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

for var in PREFIX BUILD_DIR DISTRO_DIR ; do
  if [ -z "$(eval "echo \$$var")" ]; then
    echo Missing param: $var
    usage
  fi
done

MAN_DIR=${MAN_DIR:-/usr/share/man/man1}
DOC_DIR=${DOC_DIR:-/usr/share/doc/solr}
LIB_DIR=${LIB_DIR:-/usr/lib/solr}
INSTALLED_LIB_DIR=${INSTALLED_LIB_DIR:-/usr/lib/solr}
EXAMPLES_DIR=${EXAMPLES_DIR:-$DOC_DIR/examples}
BIN_DIR=${BIN_DIR:-/usr/bin}
CONF_DIR=${CONF_DIR:-/etc/solr/conf}
DEFAULT_DIR=${ETC_DIR:-/etc/default}

VAR_DIR=$PREFIX/var

install -d -m 0755 $PREFIX/$LIB_DIR
cp -ra ${BUILD_DIR}/dist/*.*ar $PREFIX/$LIB_DIR
cp -ra ${BUILD_DIR}/dist/solrj-lib $PREFIX/$LIB_DIR/lib
cp -ra ${BUILD_DIR}/example/hdfs/collection1/conf $PREFIX/$LIB_DIR/coreconfig-template

install -d -m 0755 $PREFIX/$LIB_DIR/contrib
cp -ra ${BUILD_DIR}/contrib/velocity $PREFIX/$LIB_DIR/contrib

install -d -m 0755 $PREFIX/$LIB_DIR/server/webapps/solr
(cd $PREFIX/$LIB_DIR/server/webapps/solr ; jar xf ../../../*.war)
ln -s /var/lib/solr $PREFIX/$LIB_DIR/server/work
cp ${BUILD_DIR}/example/lib/ext/*.jar $PREFIX/$LIB_DIR/server/webapps/solr/WEB-INF/lib/

install -d -m 0755 $PREFIX/$LIB_DIR/server/webapps/ROOT
cat > $PREFIX/$LIB_DIR/server/webapps/ROOT/index.html <<__EOT__
<html><head><meta http-equiv="refresh" content="0;url=./solr"></head><body><a href="/solr">Solr Console</a></body></html>
__EOT__

install -d -m 0755 $PREFIX/$LIB_DIR/server/conf
cp $DISTRO_DIR/web.xml $PREFIX/$LIB_DIR/server/conf
cp $DISTRO_DIR/server.xml $PREFIX/$LIB_DIR/server/conf
cp $DISTRO_DIR/logging.properties $PREFIX/$LIB_DIR/server/conf

cp -ra ${BUILD_DIR}/dist/*.*ar $PREFIX/$LIB_DIR
cp -ra ${BUILD_DIR}/dist/solrj-lib $PREFIX/$LIB_DIR/lib

install -d -m 0755 $PREFIX/$LIB_DIR/bin
cp -a ${BUILD_DIR}/example/cloud-scripts/*.sh $PREFIX/$LIB_DIR/bin
sed -i -e 's#/../solr-webapp/webapp/WEB-INF/lib/#/../server/webapps/solr/WEB-INF/lib/#' $PREFIX/$LIB_DIR/bin/zkcli.sh
chmod 755 $PREFIX/$LIB_DIR/bin/*

install -d -m 0755 $PREFIX/$DOC_DIR
cp -a  ${BUILD_DIR}/*.txt $PREFIX/$DOC_DIR
cp -ra ${BUILD_DIR}/docs/* $PREFIX/$DOC_DIR
cp -ra ${BUILD_DIR}/example/ $PREFIX/$DOC_DIR/

# Copy in the configuration files
install -d -m 0755 $PREFIX/$DEFAULT_DIR
cp $DISTRO_DIR/solr.default $PREFIX/$DEFAULT_DIR/solr

install -d -m 0755 $PREFIX/${CONF_DIR}.dist
cp ${BUILD_DIR}/example/resources/log4j.properties $PREFIX/${CONF_DIR}.dist

# Copy in the wrapper
cat > $PREFIX/$LIB_DIR/bin/solrd <<EOF
#!/bin/bash

[ -f /etc/default/solr ] && . /etc/default/solr

# Autodetect JAVA_HOME if not defined
if [ -e /usr/libexec/bigtop-detect-javahome ]; then
  . /usr/libexec/bigtop-detect-javahome
elif [ -e /usr/lib/bigtop-utils/bigtop-detect-javahome ]; then
  . /usr/lib/bigtop-utils/bigtop-detect-javahome
fi

export CATALINA_HOME=$LIB_DIR/../bigtop-tomcat
export CATALINA_BASE=$LIB_DIR/server

export CATALINA_TMPDIR=\${SOLR_DATA:-/var/lib/solr/}
export CATALINA_PID=\${SOLR_RUN:-/var/run/solr/}solr.pid
export CATALINA_OUT=\${SOLR_LOG:-/var/log/solr}/solr.out

die() {
  echo "\$@" >&2
  exit 1
}

# SolrCloud and Non-SolrCloud modes should not step on each other toes,
# which means going from one to the other would require full reconfig
if [ -e \${SOLR_DATA:-/var/lib/solr/}/solr.cloud.ini ] ; then
  [ -n "\$SOLR_ZK_ENSEMBLE" ] || die "Error: Solr is configured for for SolrCloud mode but SOLR_ZK_ENSEMBLE is not set"
  CATALINA_OPTS="\${CATALINA_OPTS} -DzkHost=\${SOLR_ZK_ENSEMBLE}"
else
  [ -z "\$SOLR_ZK_ENSEMBLE" ] || die "Error: Solr is configured for for Non SolrCloud mode but SOLR_ZK_ENSEMBLE is set"
fi

if [ -n "\$SOLR_HDFS_HOME" ] ; then
  CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.hdfs.home=\${SOLR_HDFS_HOME}"
fi

if [ -n "\$SOLR_HDFS_CONFIG" ] ; then
  CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.hdfs.confdir=\${SOLR_HDFS_CONFIG}"
fi

if [ "\$SOLR_KERBEROS_ENABLED" == "true" ] ; then
  CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.hdfs.security.kerberos.enabled=\${SOLR_KERBEROS_ENABLED}"
fi

if [ -n "\$SOLR_KERBEROS_KEYTAB" ] ; then
  CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.hdfs.security.kerberos.keytabfile=\${SOLR_KERBEROS_KEYTAB}"
fi

if [ -n "\$SOLR_KERBEROS_PRINCIPAL" ] ; then
  CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.hdfs.security.kerberos.principal=\${SOLR_KERBEROS_PRINCIPAL}"
fi

# FIXME: we need to set this because of the jetty-centric default solr.xml
CATALINA_OPTS="\${CATALINA_OPTS} -Dhost=\$HOSTNAME -Djetty.port=\${SOLR_PORT:-8080}"

export CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.host=\$HOSTNAME
                                        -Dsolr.port=\${SOLR_PORT:-8080}
                                        -Dlog4j.configuration=file://\${SOLR_LOG4J_CONFIG:-/etc/solr/conf/log4j.properties}
                                        -Dsolr.log=\${SOLR_LOG:-/var/log/solr}
                                        -Dsolr.admin.port=\${SOLR_ADMIN_PORT:-8081}
                                        -Dsolr.solr.home=\${SOLR_HOME:-/var/lib/solr}"

# FIXME: for some reason catalina doesn't use CATALINA_OPTS for stop action
#        and thus doesn't know the admin port
export JAVA_OPTS="\$CATALINA_OPTS"

exec \${CATALINA_HOME}/bin/catalina.sh "\$@"
EOF
chmod 755 $PREFIX/$LIB_DIR/bin/solrd

# installing the only script that goes into /usr/bin
install -D -m 0755 ${BUILD_DIR}/example/cloud-scripts/solrctl.sh $PREFIX/usr/bin/solrctl

# precreating /var layout
install -d -m 0755 $VAR_DIR/log/solr
install -d -m 0755 $VAR_DIR/run/solr
install -d -m 0755 $VAR_DIR/lib/solr

# Cloudera specific
install -d -m 0755 $PREFIX/$LIB_DIR/cloudera
cp cloudera/cdh_version.properties $PREFIX/$LIB_DIR/cloudera/
