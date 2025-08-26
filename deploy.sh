#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Guacamole Deployment with Keycloak SSO ===${NC}"

# Check if running as administrator user
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root!${NC}"
   exit 1
fi

# Load database environment
GUACAMOLE_ENV="/home/administrator/projects/secrets/guacamole.env"
if [ ! -f "$GUACAMOLE_ENV" ]; then
    echo -e "${RED}Guacamole environment file not found!${NC}"
    echo "Run ./initdatabase.sh first"
    exit 1
fi
source "$GUACAMOLE_ENV"

# Load SSO environment
SSO_ENV="/home/administrator/projects/secrets/guacamole-sso.env"
if [ ! -f "$SSO_ENV" ]; then
    echo -e "${RED}SSO environment file not found!${NC}"
    echo "Run ./setup-keycloak-sso.sh first"
    exit 1
fi
source "$SSO_ENV"

# Check if PostgreSQL is running
if ! docker ps --format '{{.Names}}' | grep -qx "postgres"; then
    echo -e "${RED}PostgreSQL container is not running!${NC}"
    exit 1
fi

# Check if Keycloak is running
if ! curl -s "${OPENID_ISSUER}/.well-known/openid-configuration" >/dev/null 2>&1; then
    echo -e "${RED}Keycloak is not reachable at ${OPENID_ISSUER}${NC}"
    exit 1
fi

# Stop and remove existing containers
echo -e "${YELLOW}Stopping existing Guacamole containers...${NC}"
docker kill guacd-traefik guacamole-traefik 2>/dev/null || true
docker rm guacd-traefik guacamole-traefik 2>/dev/null || true

# Create networks if needed
echo -e "${YELLOW}Setting up networks...${NC}"
docker network create guacamole-net 2>/dev/null || echo "Network guacamole-net already exists"
docker network create traefik-proxy 2>/dev/null || echo "Network traefik-proxy already exists"

# Deploy guacd (the proxy daemon)
echo -e "${YELLOW}Deploying guacd daemon...${NC}"
docker run -d \
  --name guacd-traefik \
  --restart unless-stopped \
  --network guacamole-net \
  guacamole/guacd:latest

# Wait for guacd to start
sleep 5

# Deploy Guacamole with SSO and Traefik labels
echo -e "${YELLOW}Deploying Guacamole with Keycloak SSO...${NC}"
docker run -d \
  --name guacamole-traefik \
  --restart unless-stopped \
  --network guacamole-net \
  -e POSTGRESQL_HOSTNAME="$POSTGRES_HOSTNAME" \
  -e POSTGRESQL_PORT="$POSTGRES_PORT" \
  -e POSTGRESQL_DATABASE="$POSTGRES_DATABASE" \
  -e POSTGRESQL_USERNAME="$POSTGRES_USER" \
  -e POSTGRESQL_PASSWORD="$POSTGRES_PASSWORD" \
  -e GUACD_HOSTNAME="guacd-traefik" \
  -e GUACD_PORT="$GUACD_PORT" \
  -e WEBAPP_CONTEXT="ROOT" \
  -e OPENID_AUTHORIZATION_ENDPOINT="$OPENID_AUTHORIZATION_ENDPOINT" \
  -e OPENID_TOKEN_ENDPOINT="$OPENID_TOKEN_ENDPOINT" \
  -e OPENID_JWKS_ENDPOINT="$OPENID_JWKS_ENDPOINT" \
  -e OPENID_ISSUER="$OPENID_ISSUER" \
  -e OPENID_CLIENT_ID="$OPENID_CLIENT_ID" \
  -e OPENID_CLIENT_SECRET="$OPENID_CLIENT_SECRET" \
  -e OPENID_REDIRECT_URI="$OPENID_REDIRECT_URI" \
  -e OPENID_USERNAME_CLAIM_TYPE="$OPENID_USERNAME_CLAIM_TYPE" \
  -e OPENID_GROUPS_CLAIM_TYPE="$OPENID_GROUPS_CLAIM_TYPE" \
  -e OPENID_SCOPE="$OPENID_SCOPE" \
  -e OPENID_ALLOWED_CLOCK_SKEW="$OPENID_ALLOWED_CLOCK_SKEW" \
  -e OPENID_MAX_TOKEN_VALIDITY="$OPENID_MAX_TOKEN_VALIDITY" \
  --label "traefik.enable=true" \
  --label "traefik.docker.network=traefik-proxy" \
  --label "traefik.http.routers.guacamole.rule=Host(\`guacamole.ai-servicers.com\`)" \
  --label "traefik.http.routers.guacamole.entrypoints=websecure" \
  --label "traefik.http.routers.guacamole.tls=true" \
  --label "traefik.http.routers.guacamole.tls.certresolver=letsencrypt" \
  --label "traefik.http.services.guacamole.loadbalancer.server.port=8080" \
  --label "traefik.http.routers.guacamole-http.rule=Host(\`guacamole.ai-servicers.com\`)" \
  --label "traefik.http.routers.guacamole-http.entrypoints=web" \
  --label "traefik.http.routers.guacamole-http.middlewares=https-redirect" \
  --label "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https" \
  guacamole/guacamole:latest

# Connect to networks
echo -e "${YELLOW}Connecting to networks...${NC}"
docker network connect traefik-proxy guacamole-traefik
docker network connect postgres-net guacamole-traefik 2>/dev/null || echo "Already connected to postgres-net"
docker network connect postgres-net guacd-traefik 2>/dev/null || echo "guacd already connected to postgres-net"
docker network connect guacamole-net postgres 2>/dev/null || echo "postgres already connected to guacamole-net"

echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Health check
echo ""
echo -e "${YELLOW}=== Health Check ===${NC}"

# Check containers
if docker ps | grep -q "guacd-traefik.*Up"; then
    echo -e "${GREEN}✓ guacd daemon running${NC}"
else
    echo -e "${RED}✗ guacd daemon issues${NC}"
fi

if docker ps | grep -q "guacamole-traefik.*Up"; then
    echo -e "${GREEN}✓ Guacamole web app running${NC}"
else
    echo -e "${RED}✗ Guacamole web app issues${NC}"
fi

# Check Traefik network
if docker network inspect traefik-proxy | grep -q "guacamole-traefik"; then
    echo -e "${GREEN}✓ Connected to Traefik network${NC}"
else
    echo -e "${RED}✗ Not on Traefik network${NC}"
fi

# Check SSO configuration
echo -e "${YELLOW}Checking SSO configuration...${NC}"
if docker exec guacamole-traefik printenv | grep -q "OPENID_CLIENT_ID=$OPENID_CLIENT_ID"; then
    echo -e "${GREEN}✓ SSO configured with client ID: $OPENID_CLIENT_ID${NC}"
else
    echo -e "${RED}✗ SSO configuration issues${NC}"
fi

# Test local access
if curl -s -H "Host: guacamole.ai-servicers.com" https://localhost -k 2>/dev/null | grep -q "ng-app"; then
    echo -e "${GREEN}✓ Guacamole responding via Traefik${NC}"
else
    echo -e "${YELLOW}⚠ Cannot verify Traefik routing locally${NC}"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${GREEN}Access Methods:${NC}"
echo "1. Via Keycloak SSO: https://guacamole.ai-servicers.com/"
echo "   - Will redirect to Keycloak for authentication"
echo "   - Users in 'administrators' group get admin access"
echo ""
echo "2. Direct database login (fallback):"
echo "   - Username: guacadmin"
echo "   - Password: guacadmin"
echo ""
echo -e "${YELLOW}SSO Configuration:${NC}"
echo "  Keycloak: ${OPENID_ISSUER}"
echo "  Client ID: ${OPENID_CLIENT_ID}"
echo "  Groups claim: ${OPENID_GROUPS_CLAIM_TYPE}"
echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo "  Check logs: docker logs guacamole-traefik --tail 50"
echo "  Check SSO: docker exec guacamole-traefik printenv | grep OPENID"
echo "  Check Keycloak: ${OPENID_ISSUER}"
echo ""
echo -e "${YELLOW}Note: First SSO login may take longer as user is provisioned${NC}"