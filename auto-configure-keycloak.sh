#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Automated Keycloak Client Setup ===${NC}"
echo ""

# Keycloak settings
KEYCLOAK_URL="https://keycloak.ai-servicers.com"
REALM="master"

# Prompt for admin password
echo -e "${YELLOW}Enter Keycloak admin password:${NC}"
read -s ADMIN_PASSWORD
echo ""

echo -e "${YELLOW}Getting admin access token...${NC}"

# Get access token
TOKEN_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" 2>/dev/null)

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}Failed to get access token. Check admin password.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully authenticated${NC}"

# Check if client exists and delete if it does
echo -e "${YELLOW}Checking for existing guacamole client...${NC}"
CLIENTS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

CLIENT_ID=$(echo $CLIENTS | sed -n 's/.*"id":"\([^"]*\)".*"clientId":"guacamole".*/\1/p')

if [ ! -z "$CLIENT_ID" ]; then
    echo -e "${YELLOW}Found existing client, removing...${NC}"
    curl -s -X DELETE "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_ID" \
      -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null
    echo -e "${GREEN}✓ Removed old client${NC}"
fi

# Create new client
echo -e "${YELLOW}Creating new guacamole client...${NC}"

CREATE_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "guacamole",
    "name": "Apache Guacamole",
    "description": "Remote Desktop Gateway with SSO",
    "rootUrl": "https://guacamole.ai-servicers.com",
    "adminUrl": "https://guacamole.ai-servicers.com",
    "baseUrl": "https://guacamole.ai-servicers.com",
    "surrogateAuthRequired": false,
    "enabled": true,
    "alwaysDisplayInConsole": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "",
    "redirectUris": [
      "https://guacamole.ai-servicers.com/*"
    ],
    "webOrigins": [
      "https://guacamole.ai-servicers.com"
    ],
    "notBefore": 0,
    "bearerOnly": false,
    "consentRequired": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false,
    "publicClient": false,
    "frontchannelLogout": false,
    "protocol": "openid-connect",
    "attributes": {
      "saml.force.post.binding": "false",
      "saml.multivalued.roles": "false",
      "frontchannel.logout.session.required": "false",
      "oauth2.device.authorization.grant.enabled": "false",
      "backchannel.logout.revoke.offline.tokens": "false",
      "saml.server.signature.keyinfo.ext": "false",
      "use.refresh.tokens": "true",
      "oidc.ciba.grant.enabled": "false",
      "backchannel.logout.session.required": "true",
      "client_credentials.use_refresh_token": "false",
      "require.pushed.authorization.requests": "false",
      "saml.client.signature": "false",
      "id.token.as.detached.signature": "false",
      "saml.assertion.signature": "false",
      "saml.encrypt": "false",
      "saml.server.signature": "false",
      "exclude.session.state.from.auth.response": "false",
      "saml.artifact.binding": "false",
      "saml_force_name_id_format": "false",
      "acr.loa.map": "{}",
      "tls.client.certificate.bound.access.tokens": "false",
      "saml.authnstatement": "false",
      "display.on.consent.screen": "false",
      "token.response.type.bearer.lower-case": "false",
      "saml.onetimeuse.condition": "false"
    },
    "authenticationFlowBindingOverrides": {},
    "fullScopeAllowed": true,
    "nodeReRegistrationTimeout": -1,
    "defaultClientScopes": [
      "web-origins",
      "profile",
      "roles",
      "email"
    ],
    "optionalClientScopes": [
      "address",
      "phone",
      "offline_access",
      "microprofile-jwt"
    ]
  }' 2>/dev/null)

echo -e "${GREEN}✓ Client created${NC}"

# Get the new client ID
echo -e "${YELLOW}Getting client details...${NC}"
CLIENTS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

CLIENT_ID=$(echo $CLIENTS | sed -n 's/.*"id":"\([^"]*\)".*"clientId":"guacamole".*/\1/p')

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}Failed to create client${NC}"
    exit 1
fi

# Generate new client secret
echo -e "${YELLOW}Generating client secret...${NC}"
curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_ID/client-secret" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null

# Get the client secret
SECRET_RESPONSE=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_ID/client-secret" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

CLIENT_SECRET=$(echo $SECRET_RESPONSE | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')

echo -e "${GREEN}✓ Client secret generated: $CLIENT_SECRET${NC}"

# Create administrators group if it doesn't exist
echo -e "${YELLOW}Checking for administrators group...${NC}"
GROUPS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/groups?search=administrators" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" 2>/dev/null)

if ! echo "$GROUPS" | grep -q '"name":"administrators"'; then
    echo -e "${YELLOW}Creating administrators group...${NC}"
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "administrators"
      }' 2>/dev/null
    echo -e "${GREEN}✓ Created administrators group${NC}"
else
    echo -e "${GREEN}✓ Administrators group already exists${NC}"
fi

# Update SSO environment file
echo -e "${YELLOW}Updating SSO configuration file...${NC}"
SSO_ENV="/home/administrator/projects/secrets/guacamole-sso.env"

cat > "$SSO_ENV" << EOF
# Guacamole Keycloak SSO Configuration
# Auto-configured: $(date +%Y-%m-%d)

# OpenID Connect settings for Keycloak
OPENID_AUTHORIZATION_ENDPOINT=$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/auth
OPENID_TOKEN_ENDPOINT=$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token
OPENID_JWKS_ENDPOINT=$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/certs
OPENID_ISSUER=$KEYCLOAK_URL/realms/$REALM
OPENID_CLIENT_ID=guacamole
OPENID_CLIENT_SECRET=$CLIENT_SECRET
OPENID_REDIRECT_URI=https://guacamole.ai-servicers.com/

# User attribute mapping
OPENID_USERNAME_CLAIM_TYPE=preferred_username
OPENID_GROUPS_CLAIM_TYPE=groups
OPENID_SCOPE=openid profile email

# Settings
OPENID_MAX_TOKEN_VALIDITY=60
OPENID_ALLOWED_CLOCK_SKEW=5
EOF

echo -e "${GREEN}✓ Updated $SSO_ENV${NC}"

echo ""
echo -e "${GREEN}=== Configuration Complete ===${NC}"
echo ""
echo -e "${BLUE}Client Details:${NC}"
echo "  Client ID: guacamole"
echo "  Client Secret: $CLIENT_SECRET"
echo "  Redirect URI: https://guacamole.ai-servicers.com/*"
echo ""
echo -e "${YELLOW}Redeploying Guacamole with new configuration...${NC}"
echo ""

# Redeploy Guacamole
cd /home/administrator/projects/guacamole
./deploy.sh

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${GREEN}To test SSO:${NC}"
echo "1. Clear your browser cache/cookies"
echo "2. Go to: https://guacamole.ai-servicers.com/"
echo "3. You should be redirected to Keycloak automatically"
echo "   OR try: https://guacamole.ai-servicers.com/#/login/openid"
echo ""
echo -e "${YELLOW}To give admin access:${NC}"
echo "1. In Keycloak, go to Users"
echo "2. Select your user"
echo "3. Go to Groups tab"
echo "4. Join 'administrators' group"