#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: mosys
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/reliatec-gmbh/LibreClinica

# ============================================================================
# APP CONFIGURATION
# ============================================================================
APP="LibreClinica"
var_tags="${var_tags:-medical;research}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# ============================================================================
# INITIALIZATION
# ============================================================================
header_info "$APP"
variables
color
catch_errors

# ============================================================================
# UPDATE FUNCTION
# ============================================================================
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/tomcat9/webapps/libreclinica.war ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "libreclinica" "reliatec-gmbh/LibreClinica"; then
    msg_info "Stopping ${APP}"
    systemctl stop libreclinica
    msg_ok "Stopped ${APP}"

    msg_info "Backing up database"
    BACKUP_DATE=$(date +%F)
    $STD sudo -u postgres pg_dump libreclinica >"/root/libreclinica-db-backup-${BACKUP_DATE}.sql"
    msg_ok "Backed up database to /root/libreclinica-db-backup-${BACKUP_DATE}.sql"

    msg_info "Removing old deployment"
    rm -f /opt/tomcat9/webapps/libreclinica.war
    rm -rf /opt/tomcat9/webapps/libreclinica
    msg_ok "Removed old deployment"

    msg_info "Downloading ${APP}"
    USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
      "libreclinica" "reliatec-gmbh/LibreClinica" \
      "singlefile" "latest" "/tmp/lc_download" "LibreClinica-web-*.war"
    msg_ok "Downloaded ${APP}"

    msg_info "Deploying new WAR"
    WAR_FILE=$(find /tmp/lc_download -maxdepth 1 -name "LibreClinica-web-*.war" | head -1)
    [[ -z "$WAR_FILE" ]] && { msg_error "WAR file not found after download"; exit 1; }
    cp "$WAR_FILE" /opt/tomcat9/webapps/libreclinica.war
    chown tomcat:tomcat /opt/tomcat9/webapps/libreclinica.war
    rm -rf /tmp/lc_download
    msg_ok "Deployed new WAR"

    msg_info "Starting ${APP}"
    systemctl start libreclinica
    msg_ok "Started ${APP}"
    msg_ok "Updated successfully! Database schema migrations applied automatically on startup."
  fi
  exit
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/libreclinica${CL}"
echo -e "${INFO}${YW} Note: Tomcat may take 60-90 seconds to deploy on first start.${CL}"
echo -e "${INFO}${YW} Default credentials: ${BGN}root${CL} / ${BGN}12345678${CL} — change immediately!${CL}"
