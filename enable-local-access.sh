#!/bin/bash

# Enable local access to Guacamole
# This script adds a host port mapping for local access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Guacamole Local Access Setup${NC}"
echo -e "${BLUE}========================================${NC}"

# Configuration
LOCAL_PORT=8090
CONTAINER_NAME="guacamole-local"

echo -e "\n${YELLOW}Current Guacamole access:${NC}"
echo "  External: https://guacamole.ai-servicers.com (via Traefik)"
echo "  Internal: Container IPs only (no host port)"

echo -e "\n${YELLOW}Setting up local access on port ${LOCAL_PORT}...${NC}"

# Check if a local version is already running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}Stopping existing local container...${NC}"
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
fi

# Check if port is available
if netstat -tuln 2>/dev/null | grep -q ":${LOCAL_PORT} " || ss -tuln 2>/dev/null | grep -q ":${LOCAL_PORT} "; then
    echo -e "${RED}✗ Port ${LOCAL_PORT} is already in use!${NC}"
    echo "Please choose a different port or stop the service using it."
    exit 1
fi

# Get current Guacamole environment
echo -e "\n${YELLOW}Copying configuration from main Guacamole container...${NC}"

# Create a local-access version with port binding
echo -e "\n${YELLOW}Creating local-access container...${NC}"

# Get the environment variables from the running container
docker run -d \
  --name $CONTAINER_NAME \
  --network guacamole-net \
  -p ${LOCAL_PORT}:8080 \
  --env-file /home/administrator/projects/secrets/guacamole.env \
  --env-file /home/administrator/projects/secrets/guacamole-sso.env \
  -e WEBAPP_CONTEXT="ROOT" \
  -e GUACD_HOSTNAME="guacd" \
  -e GUACD_PORT="4822" \
  guacamole/guacamole:latest

# Connect to required networks
echo -e "${YELLOW}Connecting to networks...${NC}"
docker network connect postgres-net $CONTAINER_NAME 2>/dev/null || echo "Already connected to postgres-net"

# Wait for startup
echo -e "${YELLOW}Waiting for service to start...${NC}"
sleep 10

# Check if it's running
if docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${GREEN}✓ Local access container is running${NC}"
else
    echo -e "${RED}✗ Container failed to start${NC}"
    docker logs $CONTAINER_NAME --tail 20
    exit 1
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Local Access Enabled!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access Methods:${NC}"
echo ""
echo -e "${BLUE}1. Local Network Access:${NC}"
echo "   URL: ${GREEN}http://localhost:${LOCAL_PORT}/${NC}"
echo "   URL: ${GREEN}http://$(hostname -I | awk '{print $1}'):${LOCAL_PORT}/${NC}"
echo "   URL: ${GREEN}http://linuxserver.lan:${LOCAL_PORT}/${NC}"
echo ""
echo -e "${BLUE}2. External Access (unchanged):${NC}"
echo "   URL: ${GREEN}https://guacamole.ai-servicers.com/${NC}"
echo ""
echo -e "${YELLOW}Login Options:${NC}"
echo "  1. SSO: Click 'Login with SSO' button"
echo "  2. Database: guacadmin / guacadmin"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "  - This creates a separate container for local access"
echo "  - Both containers share the same database"
echo "  - Changes made in one are visible in the other"
echo ""
echo -e "${YELLOW}To remove local access:${NC}"
echo "  docker stop $CONTAINER_NAME"
echo "  docker rm $CONTAINER_NAME"