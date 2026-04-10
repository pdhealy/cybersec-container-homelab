FROM wazuh/wazuh-manager@sha256:366f142ebb28920c41bf77af1dcded832a21e9d4ed9a63741656b43639592ca2
USER root
RUN dnf install -y iproute && dnf clean all
RUN mkdir -p /var/lib/filebeat /var/ossec/var/start-script-lock && chown root:root /var/lib/filebeat /var/ossec/var/start-script-lock
RUN find /etc/cont-init.d/ /etc/services.d/ /etc/cont-finish.d/ /etc/s6/ -type f -exec chmod +x {} \; || true
RUN sed -i 's/rm -rf ${WAZUH_INSTALL_PATH}\/data_tmp/rm -rf ${WAZUH_INSTALL_PATH}\/data_tmp || true/g' /etc/cont-init.d/0-wazuh-init
RUN sed -i 's/LOCK="${DIR}\/var\/start-script-lock"/LOCK="\/tmp\/start-script-lock"/g' /var/ossec/bin/wazuh-control
RUN sed -i 's/MAX_ITERATION="10"/MAX_ITERATION="120"/g' /var/ossec/bin/wazuh-control
