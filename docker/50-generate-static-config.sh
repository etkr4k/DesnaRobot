#!/bin/sh
set -eu

envsubst '$WEBHOOK_SITE $WEBHOOK_APP $WEBHOOK_SCHEDULE_GET' \
  < /docker-templates/config.js.template \
  > /usr/share/nginx/html/config.js

envsubst '$WEBHOOK_SCHEDULE_GET $WEBHOOK_SCHEDULE_SET $ADMIN_TOKEN' \
  < /docker-templates/admin.config.js.template \
  > /usr/share/nginx/html/admin/config.js
