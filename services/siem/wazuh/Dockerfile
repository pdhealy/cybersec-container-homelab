FROM wazuh/wazuh-manager@sha256:366f142ebb28920c41bf77af1dcded832a21e9d4ed9a63741656b43639592ca2
USER root
RUN dnf install -y iproute && dnf clean all
RUN mkdir -p /var/lib/filebeat /var/ossec/var/start-script-lock && chown root:root /var/lib/filebeat /var/ossec/var/start-script-lock
RUN find /etc/cont-init.d/ /etc/services.d/ /etc/cont-finish.d/ /etc/s6/ -type f -exec chmod +x {} \; || true
RUN sed -i 's/rm -rf ${WAZUH_INSTALL_PATH}\/data_tmp/rm -rf ${WAZUH_INSTALL_PATH}\/data_tmp || true/g' /etc/cont-init.d/0-wazuh-init
RUN sed -i 's/LOCK="${DIR}\/var\/start-script-lock"/LOCK="\/tmp\/start-script-lock"/g' /var/ossec/bin/wazuh-control
RUN sed -i 's/MAX_ITERATION="10"/MAX_ITERATION="120"/g' /var/ossec/bin/wazuh-control
# Inject the syslog remote listener only into the FIRST <ossec_config> block.
# The base Wazuh image ossec.conf has multiple <ossec_config> blocks; using
# a done-flag prevents double-injection which causes a CRITICAL bind() error.
RUN awk '!done && /<ossec_config>/{print; print "  <remote>\n    <connection>syslog</connection>\n    <port>514</port>\n    <protocol>udp</protocol>\n    <allowed-ips>10.10.10.254</allowed-ips>\n    <allowed-ips>10.10.20.0/24</allowed-ips>\n    <allowed-ips>10.10.30.254</allowed-ips>\n    <allowed-ips>10.10.30.5</allowed-ips>\n  </remote>"; done=1; next}1' \
    /var/ossec/data_tmp/permanent/var/ossec/etc/ossec.conf > /tmp/ossec.conf && \
    mv /tmp/ossec.conf /var/ossec/data_tmp/permanent/var/ossec/etc/ossec.conf

# Root cause: the built-in iptables-2 decoder (0140-kernel_decoders.xml) has
# prematch "^\S+ IN=" which intercepts FW_FORWARD_ATTACK: messages and sets
# type=firewall, causing rule 4100 (level=0) to fire and silently discard the
# event — even with logall=yes, level-0 events are not archived.
#
# Fix: inject a named decoder for the FW_FORWARD_ATTACK prefix BEFORE the
# iptables-1/-2 decoders in the same built-in file.  Because it appears first,
# it wins.  It does NOT set type=firewall, so rule 4100 never fires.  Our
# custom rule matches on <decoded_as>fw_homelab_attack</decoded_as> at level 5
# which produces a genuine alert (alerts.log) and is archived (archives.log).
# Inject fw_homelab_attack decoder before the FIRST iptables-1 decoder only.
# (There are multiple <decoder name="iptables-1"> stanzas in the file for
# multi-pass port extraction; 0,/pat/{sub} limits replacement to first match.)
# The fw_homelab_attack decoder must include a <regex> field.  In Wazuh, a
# child decoder with ONLY <prematch> (no <regex>) does not become the recorded
# "leaf" decoder, so <decoded_as>fw_homelab_attack</decoded_as> in a rule
# would never match.  Adding a minimal regex forces Wazuh to record this as
# the final decoder for any message beginning with FW_FORWARD_ATTACK.
RUN sed -i '0,/<decoder name="iptables-1">/{s|<decoder name="iptables-1">|<decoder name="fw_homelab_attack">\n   <parent>kernel</parent>\n   <prematch>^FW_FORWARD_ATTACK </prematch>\n   <regex offset="after_prematch">^IN=(\\S+)</regex>\n   <order>id</order>\n</decoder>\n\n<decoder name="iptables-1">|}' \
    /var/ossec/ruleset/decoders/0140-kernel_decoders.xml

RUN printf '<decoder name="custom_fw_attack">\n  <program_name>^ulogd$</program_name>\n  <prematch>FW_FORWARD_ATTACK</prematch>\n</decoder>\n' \
    > /var/ossec/data_tmp/permanent/var/ossec/etc/decoders/custom_fw_attack.xml
# Rule uses <match> rather than <decoded_as> because Wazuh 4.x records child
# decoders under the parent name ('kernel'), making decoded_as unusable for
# any child of the built-in kernel decoder.  The fw_homelab_attack decoder
# fires before iptables-2, preventing type=firewall from being set and
# ensuring rule 4100 (level=0) does NOT discard the event before rule 100010.
RUN printf '<group name="attack,">\n  <rule id="100010" level="5">\n    <match>FW_FORWARD_ATTACK</match>\n    <description>Firewall detected forward attack traffic.</description>\n  </rule>\n</group>\n' \
    > /var/ossec/data_tmp/permanent/var/ossec/etc/rules/custom_fw_attack_rules.xml

# Enable logall: replace the existing <logall>no</logall> rather than appending
# a duplicate tag (which could leave the first "no" taking precedence).
RUN sed -i 's|<logall>no</logall>|<logall>yes</logall>|g' \
    /var/ossec/data_tmp/permanent/var/ossec/etc/ossec.conf
