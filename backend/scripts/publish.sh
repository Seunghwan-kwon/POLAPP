USERNAME=kinnefix
HOSTNAME=polapp.duckdns.org
PUBLISH="${1:-test}"

rsync -avz --delete dist/ $USERNAME@$HOSTNAME:/home/kinnefix/publish/$PUBLISH/server/dist/
