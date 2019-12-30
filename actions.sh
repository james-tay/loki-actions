#!/bin/bash

EVENTS="/tmp/events"
SMTP_TO="jamsie72@gmail.com"
SMTP_FROM="loki@drowningfrog.homenet.org"
SMTP_SUBJECT="loki alert events"
SMTP_SERVER="vip-smtp.drowningfrog.homenet.org"
MAILSEND="/tools/loki-actions/mailsend.pl"

case $1 in
'pre')
  rm -f $EVENTS
  ;;
'post')
  if [ -f $EVENTS ] ; then
    HEADER="/tmp/header"
    NOW=`date '+%a, %d %b %Y %H:%M:%S %z'`
    echo "From: $SMTP_FROM" >$HEADER
    echo "To: $SMTP_TO" >>$HEADER
    echo "Subject: $SMTP_SUBJECT" >>$HEADER
    echo "Date: $NOW" >>$HEADER
    echo "" >>$HEADER
    cat $HEADER $EVENTS | $MAILSEND $SMTP_SERVER
  fi
  ;;
*)
  echo "Usage: $0 < pre | post >"
  exit 1
  ;;
esac

