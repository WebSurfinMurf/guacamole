#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Insert a connection, its parameters, and guacadmin permissions atomically.
#
#   add_connection <protocol> <connection name> [param=value ...]
#
# connection_id is assigned by the guacamole_connection_connection_id_seq
# sequence (the column default) -- NEVER computed as MAX(connection_id)+1.
# Supplying the id explicitly leaves the sequence behind, and the Guacamole
# web UI (which relies on the sequence) then fails every "New Connection"
# with "duplicate key value violates unique constraint
# guacamole_connection_pkey". See CLAUDE.md "Connection ID Sequence Drift".
#
# Values are passed as psql variables, so names/passwords containing quotes
# are handled correctly. Empty parameter values are skipped.
add_connection() {
    local protocol="$1" conn_name="$2"
    shift 2

    local -a psql_args=(-U admin -d guacamole_db -t -A -q
                        -v ON_ERROR_STOP=1
                        -v protocol="$protocol"
                        -v conn_name="$conn_name")
    local values="" pair key val i=0
    for pair in "$@"; do
        key="${pair%%=*}"
        val="${pair#*=}"
        [ -z "$val" ] && continue
        psql_args+=(-v "k${i}=${key}" -v "v${i}=${val}")
        [ -n "$values" ] && values+=", "
        values+="(:'k${i}', :'v${i}')"
        i=$((i + 1))
    done

    # Single statement => implicitly atomic. Data-modifying CTEs always run,
    # so params/perms are written even though the final SELECT only reads
    # new_conn.
    docker exec -i postgres psql "${psql_args[@]}" <<SQL
WITH new_conn AS (
    INSERT INTO guacamole_connection (connection_name, protocol)
    VALUES (:'conn_name', :'protocol')
    RETURNING connection_id
), params AS (
    INSERT INTO guacamole_connection_parameter
        (connection_id, parameter_name, parameter_value)
    SELECT n.connection_id, p.name, p.value
    FROM new_conn n, (VALUES $values) AS p(name, value)
), perms AS (
    INSERT INTO guacamole_connection_permission
        (entity_id, connection_id, permission)
    SELECT e.entity_id, n.connection_id,
           g.perm::guacamole_object_permission_type
    FROM new_conn n
    CROSS JOIN guacamole_entity e
    CROSS JOIN (VALUES ('READ'), ('UPDATE'), ('DELETE'), ('ADMINISTER'))
        AS g(perm)
    WHERE e.name = 'guacadmin' AND e.type = 'USER'
    ON CONFLICT DO NOTHING
)
SELECT connection_id FROM new_conn;
SQL
}

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

        new_id=$(add_connection ssh "$conn_name" \
            "hostname=$hostname" "port=$port" "username=$username")

        echo -e "${GREEN}✓ SSH connection '$conn_name' added (id $new_id)${NC}"
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

        new_id=$(add_connection rdp "$conn_name" \
            "hostname=$hostname" "port=$port" "username=$username" \
            "security=$security" "ignore-cert=true" "domain=$domain")

        echo -e "${GREEN}✓ RDP connection '$conn_name' added (id $new_id)${NC}"
        echo -e "${YELLOW}Note: You may need to enable RDP on the target Windows machine${NC}"
        ;;

    3)
        echo -e "${GREEN}Adding VNC Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP: " hostname
        read -p "Port [5900]: " port
        port=${port:-5900}
        read -p "VNC Password (if set): " vncpass

        new_id=$(add_connection vnc "$conn_name" \
            "hostname=$hostname" "port=$port" "password=$vncpass")

        echo -e "${GREEN}✓ VNC connection '$conn_name' added (id $new_id)${NC}"
        echo -e "${YELLOW}Note: Make sure VNC server is running on the target${NC}"
        echo -e "${YELLOW}Note: If the target is a container, guacd must share a network with it${NC}"
        ;;

    4)
        echo -e "${GREEN}Adding Telnet Connection${NC}"
        read -p "Connection name: " conn_name
        read -p "Hostname/IP: " hostname
        read -p "Port [23]: " port
        port=${port:-23}
        read -p "Username: " username

        new_id=$(add_connection telnet "$conn_name" \
            "hostname=$hostname" "port=$port" "username=$username")

        echo -e "${GREEN}✓ Telnet connection '$conn_name' added (id $new_id)${NC}"
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
