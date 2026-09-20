FROM node:20-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0 AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

ARG VITE_API_BASE=http://localhost:8080
ENV VITE_API_BASE=$VITE_API_BASE

RUN npm run build

FROM nginx:alpine-slim@sha256:80149a0e5bc9fa0b8beaff5b8a453f71ba8ba038895d418381297ffa5cd57782

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

RUN sed -i 's#^[[:space:]]*pid[[:space:]].*;#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf \
    && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /var/log/nginx

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]