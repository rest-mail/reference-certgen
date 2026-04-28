FROM alpine:3.20
RUN apk add --no-cache openssl
COPY --chmod=0755 generate-certs.sh /usr/local/bin/generate-certs.sh
ENTRYPOINT ["/usr/local/bin/generate-certs.sh"]
