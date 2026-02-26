#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: mosys
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/reliatec-gmbh/LibreClinica

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ============================================================================
# DEPENDENCIES
# ============================================================================
msg_info "Installing Dependencies"
$STD apt install -y postgresql-client
msg_ok "Installed Dependencies"

# ============================================================================
# JAVA 11 + POSTGRESQL 14
# ============================================================================
JAVA_VERSION="11" setup_java

PG_VERSION="14" setup_postgresql
PG_DB_NAME="libreclinica" PG_DB_USER="clinica" setup_postgresql_db

get_lxc_ip

# ============================================================================
# TOMCAT 9 (downloaded from Apache CDN for Debian 13 compatibility)
# ============================================================================
msg_info "Installing Apache Tomcat 9"
LATEST_TC9=$(curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-9/" |
  grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+/' | sort -V | tail -n1 | tr -d '/')
TC9_VER="${LATEST_TC9#v}"
TC9_URL="https://dlcdn.apache.org/tomcat/tomcat-9/${LATEST_TC9}/bin/apache-tomcat-${TC9_VER}.tar.gz"
curl -fsSL "$TC9_URL" -o /tmp/tomcat9.tar.gz
$STD adduser --system --group --no-create-home --shell /usr/sbin/nologin tomcat
mkdir -p /opt/tomcat9
tar --strip-components=1 -xzf /tmp/tomcat9.tar.gz -C /opt/tomcat9
rm -f /tmp/tomcat9.tar.gz
# Remove default webapps (ROOT, examples, docs, host-manager, manager)
rm -rf /opt/tomcat9/webapps/*
chown -R tomcat:tomcat /opt/tomcat9
chmod -R 750 /opt/tomcat9
# Tomcat needs write access to temp and work dirs
chmod 770 /opt/tomcat9/temp /opt/tomcat9/work /opt/tomcat9/logs /opt/tomcat9/webapps
msg_ok "Installed Apache Tomcat 9 ${TC9_VER}"

# ============================================================================
# LIBRECLINICA DIRECTORIES + CONFIGURATION
# ============================================================================
msg_info "Configuring LibreClinica"
mkdir -p /opt/tomcat9/libreclinica.config
mkdir -p /opt/tomcat9/libreclinica.data
mkdir -p /opt/tomcat9/logs/libreclinica
chown -R tomcat:tomcat \
  /opt/tomcat9/libreclinica.config \
  /opt/tomcat9/libreclinica.data \
  /opt/tomcat9/logs/libreclinica

cat <<EOF >/opt/tomcat9/libreclinica.config/datainfo.properties
dbType=postgres
dbUser=${PG_DB_USER}
dbPass=${PG_DB_PASS}
db=${PG_DB_NAME}
dbPort=5432
dbHost=localhost

filePath=\${catalina.home}/libreclinica.data/
attached_file_location=

log.dir=\${catalina.home}/logs/libreclinica
logLocation=local
logLevel=info

sysURL=http://${LOCAL_IP}:8080/libreclinica/MainMenu
adminEmail=admin@example.com
maxInactiveInterval=3600

mailHost=localhost
mailPort=25
mailProtocol=smtp
mailUsername=
mailPassword=
mailSmtpAuth=false
mailSmtpStarttls.enable=false
mailSmtpsAuth=false
mailSmtpsStarttls.enable=false
mailSmtpConnectionTimeout=5000
mailErrorMsg=
userAccountNotification=email

collectStats=false
display.manual=false

2fa.activated=false
EOF

chown tomcat:tomcat /opt/tomcat9/libreclinica.config/datainfo.properties
chmod 640 /opt/tomcat9/libreclinica.config/datainfo.properties
msg_ok "Configured LibreClinica"

# ============================================================================
# DOWNLOAD AND DEPLOY LIBRECLINICA WAR
# ============================================================================
msg_info "Downloading LibreClinica"
USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
  "libreclinica" "reliatec-gmbh/LibreClinica" \
  "singlefile" "latest" "/tmp/lc_download" "LibreClinica-web-*.war"
cp /tmp/lc_download/LibreClinica-web-*.war /opt/tomcat9/webapps/libreclinica.war
chown tomcat:tomcat /opt/tomcat9/webapps/libreclinica.war
chmod 640 /opt/tomcat9/webapps/libreclinica.war
rm -rf /tmp/lc_download
msg_ok "Downloaded and deployed LibreClinica"

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================
msg_info "Creating Service"
JAVA_HOME_PATH=$(readlink -f /usr/lib/jvm/temurin-11-jdk-amd64)
cat <<EOF >/etc/systemd/system/libreclinica.service
[Unit]
Description=LibreClinica EDC (Apache Tomcat 9)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=${JAVA_HOME_PATH}
Environment=CATALINA_HOME=/opt/tomcat9
Environment=CATALINA_BASE=/opt/tomcat9
Environment=CATALINA_PID=/opt/tomcat9/temp/tomcat.pid
Environment=JAVA_OPTS="-Xms256m -Xmx768m -server -Djava.awt.headless=true"
ExecStart=/opt/tomcat9/bin/catalina.sh start
ExecStop=/opt/tomcat9/bin/catalina.sh stop
SuccessExitStatus=143
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now libreclinica
msg_ok "Created Service"

# ============================================================================
# SAVE CREDENTIALS
# ============================================================================
{
  echo "LibreClinica URL:        http://${LOCAL_IP}:8080/libreclinica"
  echo "Default admin user:      root"
  echo "Default admin password:  12345678"
  echo ""
  echo "PostgreSQL User:         ${PG_DB_USER}"
  echo "PostgreSQL Password:     ${PG_DB_PASS}"
  echo "PostgreSQL Database:     ${PG_DB_NAME}"
  echo ""
  echo "Config file: /opt/tomcat9/libreclinica.config/datainfo.properties"
} >~/libreclinica.creds

# ============================================================================
# CLEANUP
# ============================================================================
motd_ssh
customize
cleanup_lxc
