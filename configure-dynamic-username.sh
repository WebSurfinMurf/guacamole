#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Configure Dynamic Username for Connections ===${NC}"
echo ""
echo "This script configures Guacamole connections to use the authenticated"
echo "user's username instead of a hardcoded value."
echo ""

# Load database environment
GUACAMOLE_ENV="/home/administrator/projects/secrets/guacamole.env"
if [ ! -f "$GUACAMOLE_ENV" ]; then
    echo -e "${RED}Guacamole environment file not found!${NC}"
    exit 1
fi
source "$GUACAMOLE_ENV"

# Function to update connection username
update_connection_username() {
    local connection_name="$1"
    local use_dynamic="$2"
    
    if [ "$use_dynamic" = "yes" ]; then
        local new_username="\${GUAC_USERNAME}"
        echo -e "${YELLOW}Updating '$connection_name' to use dynamic username...${NC}"
    else
        echo -n "Enter username for '$connection_name': "
        read new_username
    fi
    
    export PGPASSWORD="$POSTGRES_PASSWORD"
    
    # Check if connection exists
    conn_id=$(psql -h "$POSTGRES_HOSTNAME" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -t -c \
        "SELECT connection_id FROM guacamole_connection WHERE connection_name = '$connection_name';" 2>/dev/null | xargs)
    
    if [ -z "$conn_id" ]; then
        echo -e "${RED}Connection '$connection_name' not found!${NC}"
        return 1
    fi
    
    # Update username parameter
    psql -h "$POSTGRES_HOSTNAME" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c \
        "UPDATE guacamole_connection_parameter SET parameter_value = '$new_username' 
         WHERE connection_id = $conn_id AND parameter_name = 'username';" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Updated '$connection_name' username to: $new_username${NC}"
    else
        echo -e "${RED}✗ Failed to update '$connection_name'${NC}"
        return 1
    fi
}

# Main menu
echo -e "${YELLOW}Select an option:${NC}"
echo "1. Set all connections to use dynamic username (\${GUAC_USERNAME})"
echo "2. Configure specific connection"
echo "3. View current configuration"
echo "4. Exit"
echo ""
echo -n "Choice [1-4]: "
read choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}Setting all connections to use dynamic username...${NC}"
        
        export PGPASSWORD="$POSTGRES_PASSWORD"
        connections=$(psql -h "$POSTGRES_HOSTNAME" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -t -c \
            "SELECT connection_name FROM guacamole_connection;" 2>/dev/null)
        
        while IFS= read -r conn_name; do
            conn_name=$(echo "$conn_name" | xargs)  # Trim whitespace
            if [ ! -z "$conn_name" ]; then
                update_connection_username "$conn_name" "yes"
            fi
        done <<< "$connections"
        
        echo ""
        echo -e "${GREEN}Configuration complete!${NC}"
        echo "Users will now connect with their Keycloak username."
        ;;
        
    2)
        echo ""
        export PGPASSWORD="$POSTGRES_PASSWORD"
        echo -e "${YELLOW}Available connections:${NC}"
        psql -h "$POSTGRES_HOSTNAME" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c \
            "SELECT connection_id, connection_name, protocol FROM guacamole_connection;" 2>/dev/null
        
        echo ""
        echo -n "Enter connection name to configure: "
        read conn_name
        echo -n "Use dynamic username? (yes/no): "
        read use_dynamic
        
        update_connection_username "$conn_name" "$use_dynamic"
        ;;
        
    3)
        echo ""
        echo -e "${YELLOW}Current connection configurations:${NC}"
        export PGPASSWORD="$POSTGRES_PASSWORD"
        psql -h "$POSTGRES_HOSTNAME" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c \
            "SELECT c.connection_name, c.protocol, cp.parameter_value as username
             FROM guacamole_connection c
             LEFT JOIN guacamole_connection_parameter cp 
             ON c.connection_id = cp.connection_id AND cp.parameter_name = 'username'
             ORDER BY c.connection_name;" 2>/dev/null
        ;;
        
    4)
        echo "Exiting..."
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice!${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Note:${NC}"
echo "- \${GUAC_USERNAME} will be replaced with the authenticated user's username"
echo "- This works with Keycloak SSO, LDAP, and database authentication"
echo "- Users must have accounts on the target systems with matching usernames"