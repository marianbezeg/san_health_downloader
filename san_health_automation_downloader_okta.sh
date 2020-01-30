#!/bin/bash
#--------------------------------SAN HEALTH AUTOMATION REPORT -------------------------
#
#	Description:
#
#	Download SAN Health via curl. Connection is not cert signed!
#       Aditional packages needed: jq; recode
#	Author: Marian Bezeg 
#     		
#	v1.0 - Implemenation of OKTA login
#	v1.1 - FIX: bad parsing with .jq
#--------------------------------------------------------------------------------------

########################################################################################
#------------------------------------USER CONFIG---------------------------------------#
########################################################################################
username="marian.bezeg@brocade.com"
password="test"


echo "################################################"
echo "######### SAN HEALTH AUTOMATION REPORT #########"
echo "################################################"
echo ""

#SESSION TOKEN
echo "Check login credentials..."
login_check=$(curl -s -H "Content-type: application/json"\
                -w "%{http_code}" \
		-o /dev/null \
		--data '{"username":"'"${username}"'","password":"'"${password}"'","options":{"warnBeforePasswordExpired":true,"multiOptionalFactorEnroll":false}}' \
		-X POST https://avagoext.okta.com/api/v1/authn --insecure )

if [ ${login_check} -ne "200" ]; then
echo "Login failed"
exit 1
fi

echo "Logged in.."
echo "Generating token"
session_token=$(curl -s -H "Content-type: application/json"\
                --data '{"username":"'"${username}"'","password":"'"${password}"'","options":{"warnBeforePasswordExpired":true,"multiOptionalFactorEnroll":false}}' \
	        -X POST https://avagoext.okta.com/api/v1/authn --insecure \
	        | sed -e 's/.*sessionToken":"\(.*\)","_embedded.*/\1/')

#GENERATE SAML RESPONSE

SAML_RETURN=$(curl -s -o SAML_OUTPUT.txt \
		-X GET "https://avagoext.okta.com/login/sessionCookieRedirect?token=${session_token}&redirectUrl=https://avagoext.okta.com/app/broadcomincexternal_bip_1/exk1ell9c304tTRAV1d8/sso/saml?RelayState=/group/support/san-health" \
		--insecure -c cookies.txt -b cookies.txt -L)

#PARSE SAML RESPONSE
ACTION_URL=$(cat SAML_OUTPUT.txt | grep "action=" | cut -d '"' -f4 | recode html..ascii)
SAML_RESPONSE=$(cat SAML_OUTPUT.txt | grep SAMLResponse | cut -d '"' -f6)
RELAY_STATE=$(cat SAML_OUTPUT.txt | grep RelayState | cut -d '"' -f6 )
SAML="$(echo -n $SAML_RESPONSE | recode html..ascii | tr -d '\r\n')"
RELAY="$(echo -n $RELAY_STATE | recode html..ascii)"

OUTPUT=$(curl -s \
          --data-urlencode SAMLResponse="${SAML}" \
	  --data-urlencode RelayState="${RELAY}" \
	  -X POST https://portal.broadcom.com/c/portal/saml/acs \
	  --insecure -c cookies.txt -b cookies.txt -L )

FILE_NAME=$(echo $OUTPUT| grep -o '"payload":.*' |sed 's/,"success.*//'  |  sed 's/.*payload"://' | jq -r ".[].reports|.[]|.fileName") 
AUDIT_ID=$(echo $OUTPUT| grep -o '"payload":.*' |sed 's/,"success.*//'  |  sed 's/.*payload"://' | jq -r ".[].reports|.[]|.auditId")

echo ${FILE_NAME}

while read SAN_HEALTH_NAME
      read -u 3 SAN_HEALTH_AUDIT;
do
	echo "Downloading file: ${SAN_HEALTH_NAME}"
	DOWNLOAD=$(curl -s \
                 --data-urlencode auditId="${SAN_HEALTH_AUDIT}" \
		 --data-urlencode filename="${SAN_HEALTH_NAME}" \
	 -X POST "https://portal.broadcom.com/group/support/san-health?p_p_id=SANHealth&p_p_lifecycle=2&p_p_state=normal&p_p_mode=view&p_p_resource_id=SANHealthDownloadReportResourceURL&p_p_cacheability=cacheLevelPage" \
       --insecure -c cookies.txt -b cookies.txt \
	 --output ${SAN_HEALTH_NAME}.zip )
done < <(echo "${FILE_NAME}") 3< <(echo "${AUDIT_ID}")

echo "Done :)"

