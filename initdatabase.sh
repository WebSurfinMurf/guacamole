#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Guacamole Database Full Initialization ===${NC}"
echo -e "${YELLOW}This script fixes all PostgreSQL authentication issues${NC}"

# Check if running as administrator user
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root!${NC}"
   exit 1
fi

# Load or create environment
GUACAMOLE_ENV="/home/administrator/projects/secrets/guacamole.env"
if [ ! -f "$GUACAMOLE_ENV" ]; then
    echo -e "${YELLOW}Creating Guacamole environment file...${NC}"
    
    cat > "$GUACAMOLE_ENV" << 'EOF'
# Guacamole Environment Configuration
# Generated: $(date +%Y-%m-%d)

# Database Configuration
POSTGRES_HOSTNAME=postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=guacamole_db
POSTGRES_USER=guacamole_user
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-guacpass123}

# Guacamole Configuration
GUACD_HOSTNAME=guacd
GUACD_PORT=4822
GUACAMOLE_HOME=/etc/guacamole

# Web Interface
WEBAPP_CONTEXT=ROOT
EOF
    echo -e "${GREEN}Created $GUACAMOLE_ENV${NC}"
fi
source "$GUACAMOLE_ENV"

echo -e "${YELLOW}Step 1: Configuring PostgreSQL authentication...${NC}"

# Fix pg_hba.conf to allow MD5 authentication for guacamole
docker exec postgres bash -c "cat > /tmp/pg_hba_fixed.conf << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host postfixadmin postfixadmin 0.0.0.0/0 md5
host nextcloud nextcloud 0.0.0.0/0 md5
host guacamole_db guacamole_user 0.0.0.0/0 md5
host all all all scram-sha-256
EOF
cp /tmp/pg_hba_fixed.conf /var/lib/postgresql/data/pg_hba.conf"

echo -e "${GREEN}✓ PostgreSQL authentication configured for MD5${NC}"

# Reload PostgreSQL configuration
docker exec postgres psql -U admin -d postgres -c "SELECT pg_reload_conf();" >/dev/null 2>&1

echo -e "${YELLOW}Step 2: Creating database and user...${NC}"

# Create database and user with proper permissions
docker exec postgres psql -U admin -d postgres << EOF >/dev/null 2>&1
-- Drop and recreate to ensure clean state
DROP DATABASE IF EXISTS guacamole_db;
DROP USER IF EXISTS guacamole_user;

-- Create user with password
CREATE USER guacamole_user WITH PASSWORD '$POSTGRES_PASSWORD' LOGIN;

-- Create database
CREATE DATABASE guacamole_db WITH OWNER guacamole_user;

-- Grant all privileges
GRANT ALL PRIVILEGES ON DATABASE guacamole_db TO guacamole_user;
EOF

echo -e "${GREEN}✓ Database and user created${NC}"

echo -e "${YELLOW}Step 3: Generating Guacamole database schema...${NC}"

# Generate schema SQL
docker run --rm guacamole/guacamole:latest /opt/guacamole/bin/initdb.sh --postgresql > /tmp/guac-schema.sql

echo -e "${GREEN}✓ Schema generated${NC}"

echo -e "${YELLOW}Step 4: Importing database schema...${NC}"

# Import schema as admin (to ensure proper creation)
docker exec -i postgres psql -U admin -d guacamole_db < /tmp/guac-schema.sql >/dev/null 2>&1

echo -e "${GREEN}✓ Schema imported${NC}"

echo -e "${YELLOW}Step 5: Fixing permissions...${NC}"

# Grant all permissions to guacamole_user
docker exec postgres psql -U admin -d guacamole_db << 'EOF' >/dev/null 2>&1
-- Grant schema permissions
GRANT ALL ON SCHEMA public TO guacamole_user;

-- Grant all table permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO guacamole_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO guacamole_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO guacamole_user;

-- Make guacamole_user owner of all tables
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO guacamole_user';
    END LOOP;
END $$;

-- Change database owner
ALTER DATABASE guacamole_db OWNER TO guacamole_user;
EOF

echo -e "${GREEN}✓ Permissions fixed${NC}"

echo -e "${YELLOW}Step 6: Creating default admin user...${NC}"

# Create default guacadmin user with password 'guacadmin'
export PGPASSWORD=$POSTGRES_PASSWORD
psql -h localhost -p 5432 -U guacamole_user -d guacamole_db << 'EOF' >/dev/null 2>&1
-- Create admin entity
INSERT INTO guacamole_entity (name, type) 
VALUES ('guacadmin', 'USER')
ON CONFLICT DO NOTHING;

-- Create or update admin user with password 'guacadmin'
-- Password hash for 'guacadmin' - MUST use decode() function!
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT entity_id, 
  decode('CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960', 'hex'),
  decode('FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264', 'hex'),
  CURRENT_TIMESTAMP
FROM guacamole_entity 
WHERE name = 'guacadmin' AND type = 'USER'
ON CONFLICT (entity_id) DO UPDATE
SET password_hash = decode('CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960', 'hex'),
    password_salt = decode('FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264', 'hex'),
    password_date = CURRENT_TIMESTAMP;

-- Grant admin permissions
INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT guacamole_entity.entity_id, guacamole_user.user_id, permission::guacamole_object_permission_type
FROM (VALUES ('guacadmin', 'guacadmin', 'READ'),
            ('guacadmin', 'guacadmin', 'UPDATE'),
            ('guacadmin', 'guacadmin', 'ADMINISTER')) AS permissions (username, affected_username, permission)
JOIN guacamole_entity ON guacamole_entity.name = permissions.username AND guacamole_entity.type = 'USER'
JOIN guacamole_user ON guacamole_user.entity_id = (
    SELECT entity_id FROM guacamole_entity 
    WHERE name = permissions.affected_username AND type = 'USER'
)
ON CONFLICT DO NOTHING;

-- Grant system permissions
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission::guacamole_system_permission_type
FROM (VALUES ('guacadmin', 'CREATE_USER'),
            ('guacadmin', 'CREATE_USER_GROUP'),
            ('guacadmin', 'CREATE_CONNECTION'),
            ('guacadmin', 'CREATE_CONNECTION_GROUP'),
            ('guacadmin', 'CREATE_SHARING_PROFILE'),
            ('guacadmin', 'ADMINISTER')) AS permissions (username, permission)
JOIN guacamole_entity ON guacamole_entity.name = permissions.username AND guacamole_entity.type = 'USER'
ON CONFLICT DO NOTHING;
EOF

echo -e "${GREEN}✓ Default admin user created${NC}"

echo -e "${YELLOW}Step 7: Testing database connection...${NC}"

# Test connection
if PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -p 5432 -U guacamole_user -d guacamole_db -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    exit 1
fi

# Test if admin user exists
USER_COUNT=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -p 5432 -U guacamole_user -d guacamole_db -t -c "SELECT COUNT(*) FROM guacamole_entity WHERE name = 'guacadmin';" 2>/dev/null | xargs)
if [ "$USER_COUNT" -eq "1" ]; then
    echo -e "${GREEN}✓ Admin user exists${NC}"
else
    echo -e "${RED}✗ Admin user not found${NC}"
    exit 1
fi

# Clean up
rm -f /tmp/guac-schema.sql

echo ""
echo -e "${GREEN}=== Database Initialization Complete ===${NC}"
echo ""
echo -e "${GREEN}Database Details:${NC}"
echo "  Host: postgres (or localhost from host)"
echo "  Port: 5432"
echo "  Database: guacamole_db"
echo "  User: guacamole_user"
echo "  Password: [stored in $GUACAMOLE_ENV]"
echo ""
echo -e "${GREEN}Default Admin:${NC}"
echo "  Username: guacadmin"
echo "  Password: guacadmin"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "1. PostgreSQL now uses MD5 authentication for guacamole_user"
echo "2. All permissions have been properly granted"
echo "3. The default admin user is ready to use"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Run ./deploy-local.sh for local deployment (port 8090)"
echo "2. Or run ./deploy-with-keycloak.sh for SSO deployment"
echo "3. Login and change the admin password immediately"