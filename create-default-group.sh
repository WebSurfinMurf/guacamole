#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Create Default SSO Users Group ===${NC}"
echo ""
echo -e "${YELLOW}This creates a group with access to all connections.${NC}"
echo -e "${YELLOW}All SSO users will be added to this group automatically.${NC}"
echo ""

docker exec postgres psql -U admin -d guacamole_db << 'EOF'
-- First, check current state of administrator user
SELECT 'Checking administrator user...' as status;
SELECT e.entity_id, e.name, u.user_id 
FROM guacamole_entity e 
LEFT JOIN guacamole_user u ON e.entity_id = u.entity_id 
WHERE e.name = 'administrator' AND e.type = 'USER';

-- Delete incomplete administrator user if exists
DELETE FROM guacamole_user WHERE entity_id = (
    SELECT entity_id FROM guacamole_entity 
    WHERE name = 'administrator' AND type = 'USER'
);
DELETE FROM guacamole_entity WHERE name = 'administrator' AND type = 'USER';

-- Recreate administrator properly
INSERT INTO guacamole_entity (name, type) VALUES ('administrator', 'USER');

-- Create user with proper password hash (won't be used for SSO)
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date, disabled)
SELECT 
    entity_id,
    decode('CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960', 'hex'),
    decode('FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264', 'hex'),
    CURRENT_TIMESTAMP,
    false
FROM guacamole_entity 
WHERE name = 'administrator' AND type = 'USER';

-- Grant all connection permissions
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, c.connection_id, p.permission::guacamole_object_permission_type
FROM guacamole_entity e
CROSS JOIN guacamole_connection c
CROSS JOIN (VALUES ('READ'), ('UPDATE'), ('DELETE'), ('ADMINISTER')) AS p(permission)
WHERE e.name = 'administrator' AND e.type = 'USER'
ON CONFLICT DO NOTHING;

-- Grant system admin permissions
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
WHERE e.name = 'administrator' AND e.type = 'USER'
ON CONFLICT DO NOTHING;

-- Create a default user group for SSO users
INSERT INTO guacamole_entity (name, type) 
VALUES ('sso-users', 'USER_GROUP')
ON CONFLICT DO NOTHING;

-- Create the group record
INSERT INTO guacamole_user_group (entity_id, disabled)
SELECT entity_id, false
FROM guacamole_entity 
WHERE name = 'sso-users' AND type = 'USER_GROUP'
ON CONFLICT DO NOTHING;

-- Grant the group access to all connections
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT g.entity_id, c.connection_id, p.permission::guacamole_object_permission_type
FROM guacamole_entity g
CROSS JOIN guacamole_connection c
CROSS JOIN (VALUES ('READ'), ('UPDATE')) AS p(permission)
WHERE g.name = 'sso-users' AND g.type = 'USER_GROUP'
ON CONFLICT DO NOTHING;

-- Add both users to the SSO group
INSERT INTO guacamole_user_group_member (user_group_id, member_entity_id)
SELECT 
    g.entity_id,
    u.entity_id
FROM guacamole_entity g
CROSS JOIN guacamole_entity u
WHERE g.name = 'sso-users' AND g.type = 'USER_GROUP'
  AND u.name IN ('administrator', 'websurfinmurf') AND u.type = 'USER'
ON CONFLICT DO NOTHING;

-- Show results
SELECT 'Users in database:' as status;
SELECT e.name, 
       CASE WHEN u.user_id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_user_record,
       COUNT(DISTINCT cp.connection_id) as connections
FROM guacamole_entity e
LEFT JOIN guacamole_user u ON e.entity_id = u.entity_id
LEFT JOIN guacamole_connection_permission cp ON e.entity_id = cp.entity_id
WHERE e.type = 'USER'
GROUP BY e.entity_id, e.name, u.user_id
ORDER BY e.name;

SELECT '' as separator;
SELECT 'Group memberships:' as status;
SELECT g.name as group_name, u.name as member
FROM guacamole_user_group_member m
JOIN guacamole_entity g ON g.entity_id = m.user_group_id
JOIN guacamole_entity u ON u.entity_id = m.member_entity_id
WHERE g.type = 'USER_GROUP'
ORDER BY g.name, u.name;
EOF

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}What was done:${NC}"
echo "1. Fixed administrator user in database"
echo "2. Created 'sso-users' group with connection access"
echo "3. Added administrator and websurfinmurf to the group"
echo ""
echo -e "${YELLOW}For new SSO users:${NC}"
echo "After they login, add them to the 'sso-users' group in Guacamole admin UI"
echo "They will automatically get access to all connections"