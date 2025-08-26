#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Provision SSO Users in Database ===${NC}"
echo ""
echo -e "${YELLOW}This creates 'shadow' database users for SSO authentication.${NC}"
echo -e "${YELLOW}SSO handles authentication, database provides permissions.${NC}"
echo ""

# Ask for usernames to provision
echo -e "${BLUE}Enter SSO usernames to provision (comma-separated):${NC}"
echo -e "${YELLOW}Example: admin1,user1,user2${NC}"
read -p "Usernames: " usernames

# Convert comma-separated to SQL array format
IFS=',' read -ra USERS <<< "$usernames"

for username in "${USERS[@]}"; do
    # Trim whitespace
    username=$(echo "$username" | xargs)
    
    echo -e "${YELLOW}Provisioning user: $username${NC}"
    
    docker exec postgres psql -U admin -d guacamole_db << EOF
-- Create user entity
INSERT INTO guacamole_entity (name, type) 
VALUES ('$username', 'USER')
ON CONFLICT DO NOTHING;

-- Create user record (no password - SSO handles auth)
INSERT INTO guacamole_user (entity_id, disabled)
SELECT entity_id, false
FROM guacamole_entity 
WHERE name = '$username' AND type = 'USER'
ON CONFLICT (entity_id) DO NOTHING;

-- Grant connection permissions (READ and UPDATE)
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, p.permission::guacamole_object_permission_type
FROM guacamole_entity e
CROSS JOIN guacamole_connection c
CROSS JOIN (VALUES ('READ'), ('UPDATE')) AS p(permission)
WHERE e.name = '$username' AND e.type = 'USER'
ON CONFLICT DO NOTHING;

-- Check if user is in administrators group (based on naming convention)
-- Grant admin permissions if username contains 'admin' or is specifically listed
DO \$\$
BEGIN
    IF '$username' LIKE '%admin%' THEN
        INSERT INTO guacamole_system_permission (entity_id, permission)
        SELECT e.entity_id, p.permission::guacamole_system_permission_type
        FROM guacamole_entity e
        CROSS JOIN (VALUES 
            ('CREATE_CONNECTION'),
            ('CREATE_CONNECTION_GROUP'),
            ('CREATE_SHARING_PROFILE'),
            ('CREATE_USER'),
            ('CREATE_USER_GROUP'),
            ('ADMINISTER')
        ) AS p(permission)
        WHERE e.name = '$username' AND e.type = 'USER'
        ON CONFLICT DO NOTHING;
        
        RAISE NOTICE 'Admin permissions granted to %', '$username';
    END IF;
END\$\$;
EOF
    
    echo -e "${GREEN}✓ User $username provisioned${NC}"
done

echo ""
echo -e "${YELLOW}Checking provisioned users and their permissions:${NC}"

docker exec postgres psql -U admin -d guacamole_db << 'EOF'
SELECT 
    e.name as username,
    CASE WHEN u.user_id IS NOT NULL THEN 'Yes' ELSE 'No' END as in_database,
    COUNT(DISTINCT cp.connection_id) as connections,
    CASE WHEN COUNT(sp.permission) > 0 THEN 'Admin' ELSE 'User' END as role
FROM guacamole_entity e
LEFT JOIN guacamole_user u ON e.entity_id = u.entity_id
LEFT JOIN guacamole_connection_permission cp ON e.entity_id = cp.entity_id
LEFT JOIN guacamole_system_permission sp ON e.entity_id = sp.entity_id
WHERE e.type = 'USER'
GROUP BY e.entity_id, e.name, u.user_id
ORDER BY e.name;
EOF

echo ""
echo -e "${GREEN}=== Provisioning Complete ===${NC}"
echo ""
echo -e "${BLUE}How it works:${NC}"
echo "1. SSO (OpenID) authenticates the user via Keycloak"
echo "2. Database provides the connection permissions"
echo "3. Users can login via SSO and see their connections"
echo ""
echo -e "${YELLOW}Note: Users won't appear in Guacamole UI user list until they login once${NC}"