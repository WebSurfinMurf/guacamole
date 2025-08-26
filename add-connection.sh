#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       ${GREEN}Add Guacamole Connection${CYAN}                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Available Connection Types:${NC}"
echo ""
echo -e "${YELLOW}1)${NC} SSH - Secure Shell (Terminal Access)"
echo "   - Encrypted terminal access"
echo "   - File transfer support via SFTP"
echo ""
echo -e "${YELLOW}2)${NC} RDP - Remote Desktop Protocol"
echo "   - Full Windows desktop access"
echo "   - Default port: 3389"
echo ""
echo -e "${YELLOW}3)${NC} VNC - Virtual Network Computing"
echo "   - Cross-platform desktop sharing"
echo "   - Default port: 5900"
echo ""
echo -e "${YELLOW}4)${NC} Telnet - Unencrypted Terminal"
echo "   - Basic terminal access (not recommended)"
echo "   - Default port: 23"
echo ""
echo -e "${YELLOW}5)${NC} List Existing Connections"
echo ""
echo -e "${YELLOW}0)${NC} Exit"
echo ""

read -p "Select connection type [0-5]: " choice

case $choice in
    1)
        echo -e "${GREEN}Adding SSH Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP (e.g., linuxserver.lan): " hostname
        read -p "Port [22]: " port
        port=${port:-22}
        read -p "Username: " username
        
        # Get next connection ID
        next_id=$(docker exec postgres psql -U admin -d guacamole_db -t -c "SELECT COALESCE(MAX(connection_id), 0) + 1 FROM guacamole_connection;" | xargs)
        
        # Insert connection
        docker exec postgres psql -U admin -d guacamole_db << EOF
INSERT INTO guacamole_connection (connection_id, connection_name, protocol) 
VALUES ($next_id, '$conn_name', 'ssh');

INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
($next_id, 'hostname', '$hostname'),
($next_id, 'port', '$port'),
($next_id, 'username', '$username');

-- Grant permission to admin
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'READ'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'UPDATE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'DELETE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'ADMINISTER'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;
EOF
        
        echo -e "${GREEN}✓ SSH connection '$conn_name' added successfully!${NC}"
        ;;
        
    2)
        echo -e "${GREEN}Adding RDP Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP: " hostname
        read -p "Port [3389]: " port
        port=${port:-3389}
        read -p "Username: " username
        read -p "Domain (optional): " domain
        read -p "Security mode (nla/tls/rdp/any) [any]: " security
        security=${security:-any}
        
        # Get next connection ID
        next_id=$(docker exec postgres psql -U admin -d guacamole_db -t -c "SELECT COALESCE(MAX(connection_id), 0) + 1 FROM guacamole_connection;" | xargs)
        
        # Insert connection
        docker exec postgres psql -U admin -d guacamole_db << EOF
INSERT INTO guacamole_connection (connection_id, connection_name, protocol) 
VALUES ($next_id, '$conn_name', 'rdp');

INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
($next_id, 'hostname', '$hostname'),
($next_id, 'port', '$port'),
($next_id, 'username', '$username'),
($next_id, 'security', '$security'),
($next_id, 'ignore-cert', 'true');

$([ ! -z "$domain" ] && echo "INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES ($next_id, 'domain', '$domain');")

-- Grant permission to admin
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'READ'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'UPDATE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'DELETE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'ADMINISTER'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;
EOF
        
        echo -e "${GREEN}✓ RDP connection '$conn_name' added successfully!${NC}"
        echo -e "${YELLOW}Note: You may need to enable RDP on the target Windows machine${NC}"
        ;;
        
    3)
        echo -e "${GREEN}Adding VNC Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP: " hostname
        read -p "Port [5900]: " port
        port=${port:-5900}
        read -p "VNC Password (if set): " vncpass
        
        # Get next connection ID
        next_id=$(docker exec postgres psql -U admin -d guacamole_db -t -c "SELECT COALESCE(MAX(connection_id), 0) + 1 FROM guacamole_connection;" | xargs)
        
        # Insert connection
        docker exec postgres psql -U admin -d guacamole_db << EOF
INSERT INTO guacamole_connection (connection_id, connection_name, protocol) 
VALUES ($next_id, '$conn_name', 'vnc');

INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
($next_id, 'hostname', '$hostname'),
($next_id, 'port', '$port');

$([ ! -z "$vncpass" ] && echo "INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES ($next_id, 'password', '$vncpass');")

-- Grant permission to admin
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'READ'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'UPDATE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'DELETE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'ADMINISTER'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;
EOF
        
        echo -e "${GREEN}✓ VNC connection '$conn_name' added successfully!${NC}"
        echo -e "${YELLOW}Note: Make sure VNC server is running on the target${NC}"
        ;;
        
    4)
        echo -e "${GREEN}Adding Telnet Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP: " hostname
        read -p "Port [23]: " port
        port=${port:-23}
        read -p "Username: " username
        
        # Get next connection ID
        next_id=$(docker exec postgres psql -U admin -d guacamole_db -t -c "SELECT COALESCE(MAX(connection_id), 0) + 1 FROM guacamole_connection;" | xargs)
        
        # Insert connection
        docker exec postgres psql -U admin -d guacamole_db << EOF
INSERT INTO guacamole_connection (connection_id, connection_name, protocol) 
VALUES ($next_id, '$conn_name', 'telnet');

INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
($next_id, 'hostname', '$hostname'),
($next_id, 'port', '$port'),
($next_id, 'username', '$username');

-- Grant permission to admin
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'READ'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'UPDATE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'DELETE'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, $next_id, 'ADMINISTER'
FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT DO NOTHING;
EOF
        
        echo -e "${GREEN}✓ Telnet connection '$conn_name' added successfully!${NC}"
        echo -e "${RED}Warning: Telnet is unencrypted! Use SSH when possible.${NC}"
        ;;
        
    5)
        echo ""
        echo -e "${CYAN}=== Current Connections ===${NC}"
        docker exec postgres psql -U admin -d guacamole_db -c \
            "SELECT connection_id AS id, connection_name AS name, protocol, 
             (SELECT parameter_value FROM guacamole_connection_parameter 
              WHERE connection_id = c.connection_id AND parameter_name = 'hostname') AS hostname,
             (SELECT parameter_value FROM guacamole_connection_parameter 
              WHERE connection_id = c.connection_id AND parameter_name = 'port') AS port
             FROM guacamole_connection c ORDER BY connection_id;"
        ;;
        
    0)
        echo -e "${BLUE}Exiting...${NC}"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid option!${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Note: Refresh your Guacamole web interface to see new connections${NC}"