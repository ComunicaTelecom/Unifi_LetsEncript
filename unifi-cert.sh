#!/usr/bin/env bash

# UniFi Controller SSL Certificate Let's Encript Import Script 
# for Docker image from linuxserver/unifi-controller
# by Cumunica  <http://www.comunica.com/> CFAL
# Part of Steve Jenkins <http://www.stevejenkins.com/>
# Part of https://github.com/stevejenkins/ubnt-linux-utils/
# Incorporates ideas from https://source.sosdg.org/brielle/lets-encrypt-scripts
# Version 0.1
# Last Updated Aug 17, 2022


# CONFIGURATION OPTIONS ONLY NEEDED CHANGE THE HOSTNAME
UNIFI_HOSTNAME=unifi.thehotels.tech
UNIFI_SERVICE=unifi

# Config to Dockers
UNIFI_DIR=./data
KEYSTORE=${UNIFI_DIR}/data/keystore

# FOR LET'S ENCRYPT SSL CERTIFICATES ONLY
# Generate your Let's Encrtypt key & cert with certbot before running this script
LE_MODE=true
LE_LIVE_DIR=/etc/letsencrypt/live

PRIV_KEY=/etc/letsencrypt/live/${UNIFI_HOSTNAME}/privkey.pem
CHAIN_FILE=/etc/letsencrypt/live/${UNIFI_HOSTNAME}/fullchain.pem

# CONFIGURATION OPTIONS YOU PROBABLY SHOULDN'T CHANGE
ALIAS=unifi
PASSWORD=aircontrolenterprise

#### SHOULDN'T HAVE TO TOUCH ANYTHING PAST THIS POINT ####

printf "\nStarting UniFi Controller SSL Import...\n"

if [[ ${LE_MODE} == "true" ]]; then
	# Check to see whether LE certificate has changed
	printf "\nInspecting current SSL certificate...\n"
	if md5sum -c "${LE_LIVE_DIR}/${UNIFI_HOSTNAME}/privkey.pem.md5" &>/dev/null; then
		# MD5 remains unchanged, exit the script
		printf "\nCertificate is unchanged, no update is necessary.\n"
		exit 0
	else
	# MD5 is different, so it's time to get busy!
	printf "\nUpdated SSL certificate available. Proceeding with import...\n"
	fi
fi

# Verify required files exist
if [[ ! -f ${PRIV_KEY} ]] || [[ ! -f ${CHAIN_FILE} ]]; then
	printf "\nMissing one or more required files. Check your settings.\n"
	exit 1
else
	# Everything looks OK to proceed
	printf "\nImporting the following files:\n"
	printf "Private Key: %s\n" "$PRIV_KEY"
	printf "CA File: %s\n" "$CHAIN_FILE"
fi


#Search a docker id 
DOCKER_ID=$(docker ps -aqf "name=unifi")

# Stop the UniFi Controller
printf "\nStopping UniFi Controller...\n"
docker exec -it ${DOCKER_ID} service "${UNIFI_SERVICE}" stop

if [[ ${LE_MODE} == "true" ]]; then
	
	# Write a new MD5 checksum based on the updated certificate	
	printf "\nUpdating certificate MD5 checksum...\n"

	md5sum "${PRIV_KEY}" > "${LE_LIVE_DIR}/${UNIFI_HOSTNAME}/privkey.pem.md5"
	
fi

# Create double-safe keystore backup
if [[ -s "${KEYSTORE}.orig" ]]; then
	printf "\nBackup of original keystore exists!\n"
	printf "\nCreating non-destructive backup as keystore.bak...\n"
	cp "${KEYSTORE}" "${KEYSTORE}.bak"
else
	cp "${KEYSTORE}" "${KEYSTORE}.orig"
	printf "\nNo original keystore backup found.\n"
	printf "\nCreating backup as keystore.orig...\n"
fi
	 
# Export your existing SSL key, cert, and CA data to a PKCS12 file
printf "\nExporting SSL certificate and key data into temporary PKCS12 file...\n"

#If there is a signed crt we should include this in the export

openssl pkcs12 -export \
-in "${CHAIN_FILE}" \
-inkey "${PRIV_KEY}" \
-out ./certs/temp -passout pass:"${PASSWORD}" \
-name "${ALIAS}"

	
# Delete the previous certificate data from keystore to avoid "already exists" message
printf "\nRemoving previous certificate data from UniFi keystore...\n"
docker exec -it ${DOCKER_ID}  keytool -delete -alias "${ALIAS}" -keystore /config/data/keystore -deststorepass "${PASSWORD}"
	
# Import the temp PKCS12 file into the UniFi keystore
printf "\nImporting SSL certificate into UniFi keystore...\n"
docker exec -it ${DOCKER_ID} keytool -importkeystore -srckeystore /certs/temp -srcstoretype PKCS12 -srcstorepass "${PASSWORD}" -destkeystore /config/data/keystore -deststorepass "${PASSWORD}" -destkeypass "${PASSWORD}" -alias "${ALIAS}" -trustcacerts

# Clean up temp files
printf "\nRemoving temporary files...\n"
rm -f ./certs/temp
	
# Restart the UniFi Controller to pick up the updated keystore
printf "\nRestarting UniFi Controller to apply new Let's Encrypt SSL certificate...\n"
docker restart ${DOCKER_ID} 

# That's all, folks!
printf "\nDone!\n"

exit 0
