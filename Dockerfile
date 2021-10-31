#
# DB deps
#

FROM alpine:3.14 as db-deps

ENV COLLECTIONS=logos

RUN \
  # Install deps
  apk add --no-cache --virtual .deps \
    curl \
    jq \
  # Download collections
  && cd /srv \
    && curl -LSs https://github.com/vanyauhalin/svg24/tarball/db | tar zx \
    && find . -depth -name vanyauhalin-svg24-* -exec mv {} db \; \
    && for cl in $COLLECTIONS; do \
      echo $(jq -r '.[]' /srv/db/$cl/$cl.json) > /srv/db/$cl/$cl.json; done

#
# DB
#

FROM mongo:5.0 as db

WORKDIR /srv/db

COPY --from=db-deps /srv/db .
COPY ci/db-init.sh init.sh

RUN chmod +x init.sh

#
# Base
#

FROM alpine:3.14 as base

ENV \
  TERM=xterm-256color \
  USER_NAME=app \
  USER_UID=1001 \
  GROUP_NAME=docker \
  GROUP_GID=999

RUN \
  # Create docker group
  delgroup ping && addgroup -g 998 ping \
  && addgroup -g $GROUP_GID $GROUP_NAME \
  # Create app user
  && mkdir -p /home/$USER_NAME \
  && adduser -s /bin/sh -D -u $USER_UID $USER_NAME \
  && chown -R $USER_NAME:$USER_NAME /home/$USER_NAME \
  && addgroup $USER_NAME $GROUP_NAME \
  # Create app dir
  && mkdir -p /srv \
  && chown -R $USER_NAME:$USER_NAME /srv

#
# API deps
#

FROM node:16-alpine3.14 as api-deps

ARG NODE_ENV

WORKDIR /srv/api

COPY wss/api .

RUN \
  apk add mongodb-tools \
  && if [ "$NODE_ENV" = "production" ]; \
    then \
      npm i --include dev \
      && npm run test \
      && npm run build; \
    else \
      npm i; \
    fi \
  && chown -R node:node .

#
# API prod
#

FROM node:16-alpine3.14 as api-prod

ARG NODE_ENV

WORKDIR /srv/api

COPY --from=api-deps /srv/api/dist dist
COPY wss/api/.nodemon-prod.json .nodemon-prod.json
COPY wss/api/package.json package.json

RUN \
  apk add mongodb-tools \
  && npm i \
  && chown -R node:node .

#
# WWW deps
#

FROM node:16-alpine3.14 as www-deps

ARG NODE_ENV

WORKDIR /srv/www

COPY wss/www .

RUN \
  if [ "$NODE_ENV" = "production" ]; \
    then \
      npm i --include dev \
      && npm run test \
      && npm run build; \
    else \
      npm i ; \
    fi \
  && chown -R node:node .

#
# WWW prod
#

FROM base as www-prod

ARG NODE_ENV

WORKDIR /srv/www

COPY --from=www-deps /srv/www/dist .

RUN chown -R $USER_NAME:$USER_NAME .

#
# Nginx brotli
#

FROM alpine:3.14 as nginx-brotli

ENV \
  NGINX_VERSION=1.21.3 \
  # NGX_BROTLI_VERSION=1.0.9
  NGX_BROTLI_COMMIT=9aec15e2aa6feea2113119ba06460af70ab3ea62

RUN \
  # Install deps
  apk add --no-cache --virtual .deps \
    curl \
    gcc \
    git \
    libc-dev \
    make \
    pcre-dev \
    zlib-dev \
  # Nginx dirs
  && mkdir -p /usr/lib/nginx/modules \
  && mkdir -p /usr/local/nginx/modules \
  # Download srcs
  && mkdir /usr/tmp \
  && cd /usr/tmp \
    && curl -LSs \
      https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz \
      | tar zx \
    && mkdir ngx_brotli-$NGX_BROTLI_COMMIT \
    && cd ngx_brotli-$NGX_BROTLI_COMMIT \
      && git clone --recursive https://github.com/google/ngx_brotli.git . \
      && git checkout $NGX_BROTLI_COMMIT \
      && git reset --hard \
    # Add module
    && cd ../nginx-$NGINX_VERSION \
      && ./configure \
        --with-compat \
        --add-dynamic-module=../ngx_brotli-$NGX_BROTLI_COMMIT \
      && make modules \
      && cp ./objs/*.so /usr/lib/nginx/modules

#
# Nginx
#

FROM nginx:1.21.3-alpine as nginx

ARG \
  DOMAIN \
  NODE_ENV

COPY --from=nginx-brotli /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY --from=nginx-brotli /usr/local/nginx/modules /usr/local/nginx/modules
COPY nginx/base.conf /etc/nginx/nginx.conf
COPY nginx/dev.conf /srv/nginx/dev.conf
COPY nginx/prod.conf /srv/nginx/prod.conf

RUN \
  mkdir -p /etc/nginx/sites \
  && if [ "$NODE_ENV" = "production" ]; \
    then \
      mv /srv/nginx/prod.conf /etc/nginx/sites/$DOMAIN.conf; \
    else \
      mv /srv/nginx/dev.conf /etc/nginx/sites/$DOMAIN.conf; \
    fi \
  && rm -rf /srv/nginx

#
# Certbot
#

FROM certbot/certbot as certbot
