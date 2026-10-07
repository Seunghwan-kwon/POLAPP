USERNAME=kinnefix
HOSTNAME=polapp.duckdns.org
PUBLISH=${1:-test}

scp build/app/outputs/flutter-apk/app-release.apk $USERNAME@$HOSTNAME:/home/kinnefix/publish/$PUBLISH/www/html/files/polapp.apk
