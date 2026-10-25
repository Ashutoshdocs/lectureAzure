FROM nginx:alpine

LABEL org.opencontainers.image.title="webappdeployment" \
      org.opencontainers.image.description="Static demo page served by NGINX" \
      org.opencontainers.image.version="1.0"

RUN rm -rf /usr/share/nginx/html/*

COPY index.html /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost/ >/dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]
