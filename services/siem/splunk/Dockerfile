FROM splunk/splunk@sha256:184e80b079f149cae1134dd6330e077fd510f4ea87216a0d6ebd4399782d648c
USER root
RUN microdnf install -y iproute || yum install -y iproute
RUN mkdir -p /opt/splunk/etc/system/local
COPY inputs.conf /opt/splunk/etc/system/local/inputs.conf
RUN chown -R splunk:splunk /opt/splunk/etc/system/local
USER ansible
