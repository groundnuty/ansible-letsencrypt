#!/bin/bash

export LOG=$(readlink -f renew.log) # TODO use trap to unset on fail
echo "$(TZ="America/Los_Angeles" date --iso-8601=seconds) Running $0" >> ${LOG}

DOMAIN=$(hostname -f)
export CERTPATH="/etc/letsencrypt/live/${DOMAIN}"
DAYS=30
POST_RENEW=$(readlink -f renew.d)

if [ ! -L ${CERTPATH}/fullchain.pem ]
then
  echo "ERROR: ${CERTPATH}/fullchain.pem does not exist, or is not a symbolic link!" >> ${LOG}
  exit 1
fi

BEFORE=$(cd ${CERTPATH}; stat -c %i $(readlink ${CERTPATH}/fullchain.pem)) # Get inode. Consider using if -ef

if ! openssl verify -CAfile ${CERTPATH}/fullchain.pem  ${CERTPATH}/cert.pem > /dev/null 2>&1
then
  echo "The certificate is invalid" >> ${LOG}
  exit 2
fi

EXPIREDATE=$(TZ="America/Los_Angeles" date --date="$(openssl x509 -enddate -noout -in ${CERTPATH}/fullchain.pem | cut -d '=' -f 2)" --iso-8601=seconds)
EXPIREDAYS=$(( ( $(date -d "$EXPIREDATE" +%s) - $(date +%s) ) / 86400 ))
echo "Certificate expires: ${EXPIREDATE} (${EXPIREDAYS} days)" >> ${LOG}

run_certbot () {
  echo "running certbot" >> ${LOG} 2>&1
  /opt/letsencrypt/certbot-auto --config /etc/letsencrypt/cli.ini certonly --webroot >> ${LOG} 2>&1
}

run_updates () {
  if [ -n ${POST_RENEW} ] && [ -d ${POST_RENEW} ]; then
    echo "Running post renew scripts" >> ${LOG} 2>&1
    run-parts ${POST_RENEW} >> ${LOG} 2>&1
  fi
}

if openssl x509 -checkend $(( ${DAYS} * 86400 )) -noout -in ${CERTPATH}/fullchain.pem
then
  echo "Certificate is good for at least ${DAYS} more days, exiting..." >> ${LOG}
else
  echo "Certificate has expired or will do so within ${DAYS} days, running certbot..." >> ${LOG}
  run_certbot
fi

AFTER=$(cd ${CERTPATH}; stat -c %i $(readlink ${CERTPATH}/fullchain.pem))

if [ ${BEFORE} -ne ${AFTER} ]
then
  echo "Certificate inode changed. Running Updates." >> ${LOG}
  run_updates
else
  echo "No changes were made." >> ${LOG}
fi

unset LOG CERTPATH
exit 0

