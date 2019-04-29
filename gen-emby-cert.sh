#!/usr/bin/env bash
# Original script from here: https://github.com/FarsetLabs/letsencrypt-helper-scripts/blob/master/letsencrypt-unifi.sh
# Modified script for Plex: https://github.com/cliffalbert/scripts/blob/master/gen-plex-cert.sh
# Modified by: Francisco García <me@belcboo.com>
# Version: 1
# Last Changed: 02/04/2018
# 04/29/2019: Modified for Emby server.

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

KEYFILE_PASS="your-cert-password-here"

while getopts "ird:e:" opt; do
    case $opt in
    i) onlyinsert="yes";;
    r) renew="yes";;
    d) domains+=("$OPTARG");;
    e) email=("$OPTARG");;
    esac
done



# Location of LetsEncrypt binary we use.  Leave unset if you want to let it find automatically
#LEBINARY="/usr/src/letsencrypt/certbot-auto"

DEFAULTLEBINARY="/usr/bin/certbot /usr/bin/letsencrypt /usr/sbin/certbot
        /usr/sbin/letsencrypt /usr/local/bin/certbot /usr/local/sbin/certbot
        /usr/local/bin/letsencrypt /usr/local/sbin/letsencrypt
        /usr/src/letsencrypt/certbot-auto /usr/src/letsencrypt/letsencrypt-auto
        /usr/src/certbot/certbot-auto /usr/src/certbot/letsencrypt-auto
        /usr/src/certbot-master/certbot-auto /usr/src/certbot-master/letsencrypt-auto"

if [[ ! -v LEBINARY ]]; then
        for i in ${DEFAULTLEBINARY}; do
                if [[ -x ${i} ]]; then
                        LEBINARY=${i}

                        echo "Found LetsEncrypt/Certbot binary at ${LEBINARY}"
                        break
                fi
        done
fi


# Command line options depending on New or Renew.
NEWCERT="--renew-by-default certonly"
RENEWCERT="-n renew"

if [[ ! -x ${LEBINARY} ]]; then
        echo "Error: LetsEncrypt binary not found in ${LEBINARY} !"
        echo "You'll need to do one of the following:"
        echo "1) Change LEBINARY variable in this script"
        echo "2) Install LE manually or via your package manager and do #1"
        echo "3) Use the included get-letsencrypt.sh script to install it"
        exit 1
fi


if [[ ! -z ${email} ]]; then
        email="--email ${email}"
else
        email=""
fi

shift $((OPTIND -1))
for val in "${domains[@]}"; do
        DOMAINS="${DOMAINS} -d ${val} "
done

MAINDOMAIN=${domains[0]}

if [[ -z ${MAINDOMAIN} ]]; then
        echo "Error: At least one -d argument is required"
        exit 1
fi

if [[ ${renew} == "yes" ]]; then
        LEOPTIONS=${RENEWCERT}
else
        LEOPTIONS="${email} ${DOMAINS} ${NEWCERT}"
fi

if [[ ${onlyinsert} != "yes" ]]; then
        echo "Firing up standalone authenticator on TCP port 80 and requesting cert..."
        ${LEBINARY} \
                --server https://acme-v01.api.letsencrypt.org/directory \
        --agree-tos \
                --standalone --preferred-challenges http-01 \
        ${LEOPTIONS}
fi    

if `md5sum -c /etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5 &>/dev/null`; then
        echo "Cert has not changed, not updating controller."
        exit 0
else
        TEMPFILE=$(mktemp)
        CATEMPFILE=$(mktemp)

        echo "Cert has changed, updating controller..."
        md5sum /etc/letsencrypt/live/${MAINDOMAIN}/cert.pem > /etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5 
        echo "Using openssl to prepare certificate..."
        cat /etc/letsencrypt/live/${MAINDOMAIN}/chain.pem >> "${CATEMPFILE}"
        openssl pkcs12 -export -out "${TEMPFILE}" \
        -passout pass:${KEYFILE_PASS} \
        -in /etc/letsencrypt/live/${MAINDOMAIN}/cert.pem \
        -inkey /etc/letsencrypt/live/${MAINDOMAIN}/privkey.pem \
        -out "${TEMPFILE}" -name plexmediaserver \
        -CAfile "${CATEMPFILE}" -caname root
        echo "Stopping Emby Server..."
        service emby-server stop
        cp "${TEMPFILE}" /var/lib/emby/certificate.pfx
        chown emby:emby /var/lib/emby/certificate.pfx
        rm -f "${TEMPFILE}" "${CATEMPFILE}"
        echo "Starting Emby Server..."
        service emby-server start
        echo "Done!"
fi