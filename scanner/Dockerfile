FROM semgrep/semgrep:latest

USER root

RUN apk add --no-cache aws-cli

COPY scanner_entrypoint.sh /usr/local/bin/scanner_entrypoint.sh
RUN chmod +x /usr/local/bin/scanner_entrypoint.sh

ENTRYPOINT ["/usr/local/bin/scanner_entrypoint.sh"]
