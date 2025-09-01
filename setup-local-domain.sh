#!/bin/bash

# Setup local domain access for Guacamole with Keycloak SSO
# This adds guacamole.linuxserver.lan as an additional access point

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Guacamole Local Domain Setup${NC}"
echo -e "${BLUE}========================================${NC}"

# Configuration
LOCAL_DOMAIN="guacamole.linuxserver.lan"
KEYCLOAK_REALM="https://keycloak.ai-servicers.com/realms/master"

echo -e "\n${YELLOW}Setting up local domain: ${LOCAL_DOMAIN}${NC}"

# First, update Keycloak to accept redirects from local domain
echo -e "\n${YELLOW}Updating Keycloak client configuration...${NC}"
echo "Please ensure the following redirect URI is added in Keycloak:"
echo "  ${GREEN}http://${LOCAL_DOMAIN}:8090/*${NC}"
echo "  ${GREEN}https://${LOCAL_DOMAIN}/*${NC}"
echo ""
echo "To add these:"
echo "1. Go to https://keycloak.ai-servicers.com/admin"
echo "2. Navigate to Clients -> guacamole"
echo "3. Add to Valid Redirect URIs:"
echo "   - http://guacamole.linuxserver.lan:8090/*"
echo "   - https://guacamole.linuxserver.lan/*"
echo "4. Save the changes"
echo ""
read -p "Press Enter when Keycloak has been updated..."

# Update the SSO environment to include local domain
echo -e "\n${YELLOW}Updating SSO configuration...${NC}"
SSO_ENV="/home/administrator/projects/secrets/guacamole-sso.env"

# Check if local domain redirect is already configured
if ! grep -q "LOCAL_REDIRECT_URI" "$SSO_ENV"; then
    echo "" >> "$SSO_ENV"
    echo "# Local domain access" >> "$SSO_ENV"
    echo "LOCAL_REDIRECT_URI=http://${LOCAL_DOMAIN}:8090" >> "$SSO_ENV"
    echo -e "${GREEN}✓ Added local redirect URI to configuration${NC}"
else
    echo -e "${YELLOW}Local redirect URI already configured${NC}"
fi

# Add /etc/hosts entry if not present
echo -e "\n${YELLOW}Checking /etc/hosts...${NC}"
if ! grep -q "$LOCAL_DOMAIN" /etc/hosts; then
    echo -e "${YELLOW}Adding $LOCAL_DOMAIN to /etc/hosts...${NC}"
    echo "127.0.0.1    $LOCAL_DOMAIN" | sudo tee -a /etc/hosts
    echo -e "${GREEN}✓ Added to /etc/hosts${NC}"
else
    echo -e "${GREEN}✓ $LOCAL_DOMAIN already in /etc/hosts${NC}"
fi

# Create a Traefik configuration for local domain (optional - for HTTPS)
echo -e "\n${YELLOW}Creating Traefik configuration for local domain...${NC}"
cat > /tmp/guacamole-local.yml << 'EOF'
# This would go in Traefik's dynamic configuration
# For local HTTPS access to Guacamole
http:
  routers:
    guacamole-local:
      rule: "Host(\`guacamole.linuxserver.lan\`)"
      entryPoints:
        - websecure
      service: guacamole-local
      tls: {}
  
  services:
    guacamole-local:
      loadBalancer:
        servers:
          - url: "http://guacamole:8080"
EOF

echo -e "${GREEN}Traefik configuration created at /tmp/guacamole-local.yml${NC}"
echo "(This would need to be added to Traefik's dynamic configuration)"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Local Domain Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access Methods:${NC}"
echo ""
echo -e "${BLUE}1. Local Domain with Port (HTTP):${NC}"
echo "   URL: ${GREEN}http://${LOCAL_DOMAIN}:8090/${NC}"
echo "   - Works immediately"
echo "   - SSO will redirect back here after auth"
echo ""
echo -e "${BLUE}2. Local Network Direct IP:${NC}"
echo "   URL: ${GREEN}http://localhost:8090/${NC}"
echo "   URL: ${GREEN}http://$(hostname -I | awk '{print $1}'):8090/${NC}"
echo ""
echo -e "${BLUE}3. External Domain (HTTPS):${NC}"
echo "   URL: ${GREEN}https://guacamole.ai-servicers.com/${NC}"
echo ""
echo -e "${YELLOW}Authentication:${NC}"
echo "  - SSO works with all URLs (after Keycloak update)"
echo "  - Database auth: guacadmin / guacadmin"
echo ""
echo -e "${YELLOW}Testing SSO with local domain:${NC}"
echo "1. Go to http://${LOCAL_DOMAIN}:8090/"
echo "2. Click 'Login with SSO'"
echo "3. Authenticate with Keycloak"
echo "4. Should redirect back to http://${LOCAL_DOMAIN}:8090/"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "  - The :8090 port is required for local HTTP access"
echo "  - For HTTPS local access, Traefik configuration would be needed"
echo "  - SSO works with both external and local domains"