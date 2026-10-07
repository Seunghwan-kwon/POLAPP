USERNAME=kinnefix
HOSTNAME=polapp.duckdns.org
PUBLISH=${1:-test}

rsync -avz build/web/ $USERNAME@$HOSTNAME:/home/kinnefix/publish/$PUBLISH/www/html/
