FROM alpine@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

RUN apk add --no-cache iptables bash tcpdump busybox-extras && \
    addgroup -g 1000 firewall && \
    adduser -u 1000 -G firewall -D firewall

COPY firewall-rules.sh /firewall-rules.sh
RUN chmod +x /firewall-rules.sh

USER 1000:1000


CMD ["/firewall-rules.sh"]
