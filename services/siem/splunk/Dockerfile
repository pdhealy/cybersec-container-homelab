FROM splunk/splunk:latest
USER root
RUN microdnf install -y iproute || yum install -y iproute
RUN mkdir -p /opt/splunk/etc/system/local
COPY inputs.conf /opt/splunk/etc/system/local/inputs.conf
RUN chown -R splunk:splunk /opt/splunk/etc/system/local
USER ansible
