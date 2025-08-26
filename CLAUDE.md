# Guacamole - Remote Access Gateway

## Project Overview
Apache Guacamole provides clientless remote desktop access via web browser. Supports SSH, RDP, VNC, and Telnet protocols.

## Current Status
- **Status**: ✅ WORKING
- **URL**: https://guacamole.ai-servicers.com/
- **Authentication**: PostgreSQL database
- **Credentials**: guacadmin/guacadmin

## Architecture
```
User Browser
    ↓
Guacamole Web App (Port 8090/8091)
    ↓
guacd Proxy Daemon (Port 4822)
    ↓
Target Servers (SSH/RDP/VNC)
```

## Deployment

### Production Deployment (Traefik)
- **Script**: `./deploy.sh`
- **Access**: Via Traefik reverse proxy
- **Auth**: PostgreSQL database
- **URL**: https://guacamole.ai-servicers.com/
- **Credentials**: guacadmin/guacadmin

### Future Enhancement
- **Keycloak SSO**: OpenID Connect integration (not yet implemented)

## Database Setup

### Initialize Database (REQUIRED for database deployments)
```bash
./initdatabase.sh
```

This script:
1. Configures PostgreSQL MD5 authentication
2. Creates guacamole_db and guacamole_user
3. Imports Guacamole schema
4. Fixes all permissions
5. Creates default admin user

## PostgreSQL Authentication Fix

### Problem
PostgreSQL uses SCRAM-SHA-256 by default, but guacamole_user had no password or wrong auth method.

### Solution (implemented in initdatabase.sh)
1. Add MD5 auth rule in pg_hba.conf BEFORE the SCRAM rule:
   ```
   host guacamole_db guacamole_user 0.0.0.0/0 md5
   ```

2. Set password properly:
   ```sql
   ALTER USER guacamole_user WITH PASSWORD 'guacpass123';
   ```

3. Grant all permissions:
   ```sql
   GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO guacamole_user;
   GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO guacamole_user;
   ```

## Files & Scripts

### Essential Scripts
- **deploy.sh** - Main deployment script for Traefik
- **initdatabase.sh** - Database initialization (run first if database not setup)
- **add-connection.sh** - Add new SSH/RDP/VNC/Telnet connections

### Configuration Files
- **/home/administrator/projects/secrets/guacamole.env** - Database credentials and configuration
- All scripts source this env file - no hardcoded passwords

## Environment Files

### /home/administrator/projects/secrets/guacamole.env
- Contains all database credentials and configuration
- Auto-created by initdatabase.sh if missing
- Used by all deployment scripts
- Keeps passwords out of scripts for security

### Security Notes
- All scripts source guacamole.env for credentials
- No hardcoded passwords in deployment scripts
- Env file has restricted permissions (only administrator user)

## Common Issues & Solutions

### 1. PostgreSQL Authentication Failed
**Symptom**: "FATAL: password authentication failed for user guacamole_user"
**Solution**: Run `./initdatabase.sh` to fix authentication

### 2. Permission Denied on Tables
**Symptom**: "ERROR: permission denied for table guacamole_user"
**Solution**: Database permissions not set. Run `./initdatabase.sh`

### 3. Container Naming Conflicts
**Symptom**: Traefik shows 404 or authentication succeeds but UI shows "Invalid login"
**Cause**: Old containers with same name still registered in Traefik
**Solution**: 
```bash
# Check for old containers
docker ps -a | grep guacamole
# Remove conflicting containers
docker rm guacamole guacd  # Remove old containers
# Redeploy with unique names (guacamole-traefik, guacd-traefik)
./deploy-traefik.sh
```

### 4. Invalid Login
**Symptom**: Login page shows but credentials don't work
**Causes**:
- Wrong password hash in database
- Database connection issues
- Using wrong URL path (/guacamole/ vs /)

### 5. SSH Connection Failed - "SSH handshake failed"
**Symptom**: After clicking SSH connection, error "The remote desktop server encountered an error"
**Cause**: Default SSH connection uses "localhost" which doesn't work from container
**Solution**: Update hostname to use DNS name or IP:
```sql
UPDATE guacamole_connection_parameter 
SET parameter_value = 'linuxserver.lan' 
WHERE connection_id = 1 AND parameter_name = 'hostname';
```

### 6. SSH Password Prompt
**Note**: After logging into Guacamole, you'll see a password prompt. This is the SSH password for your target server, NOT the Guacamole password.

## Docker Containers

- **guacamole-traefik** - Web application (via reverse proxy)
- **guacd-traefik** - Proxy daemon for protocol handling

## Networks
- guacamole-net (main network)
- guac-simple (simple deployment)
- postgres-net (database connection)
- traefik-proxy (reverse proxy)

## Available Connections

### Currently Configured
1. **Local SSH Server** - Terminal access to linuxserver.lan:22
2. **Local RDP Desktop** - Full desktop access to linuxserver.lan:3389

### Quick Commands

```bash
# Main deployment menu
./deploy.sh

# Add new connections (SSH/RDP/VNC/Telnet)
./add-connection.sh

# Check status
./deploy.sh  # Then select option 6

# View logs
docker logs guacamole-traefik --tail 50
docker logs guacd-traefik --tail 50
```

## Troubleshooting Steps

1. **Check container status**:
   ```bash
   docker ps | grep guac
   ```

2. **Check logs**:
   ```bash
   docker logs guacamole-local --tail 50 2>&1 | grep ERROR
   ```

3. **Test database connection**:
   ```bash
   export PGPASSWORD=guacpass123
   psql -h localhost -U guacamole_user -d guacamole_db -c "SELECT 1;"
   ```

4. **Check PostgreSQL auth**:
   ```bash
   docker exec postgres cat /var/lib/postgresql/data/pg_hba.conf | grep guacamole
   ```

5. **Verify Traefik routing**:
   ```bash
   docker logs traefik --tail 20 | grep guacamole
   ```

## Key Learnings

1. **PostgreSQL Password Hashing**: Use `decode()` function for hex-to-binary conversion:
   ```sql
   -- CORRECT:
   decode('CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960', 'hex')
   -- WRONG:
   E'\xCA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960'
   ```

2. **PostgreSQL Authentication**: Default SCRAM-SHA-256 incompatible with some password setups. MD5 works better for Guacamole.

3. **Container Naming**: Always use unique container names to avoid Traefik routing conflicts. Old containers can still be registered even if stopped.

4. **Session Handling**: Traefik needs sticky sessions for Guacamole authentication to work properly through reverse proxy.

5. **WEBAPP_CONTEXT**: Set to "ROOT" to serve from / instead of /guacamole/ path.

6. **Permissions Matter**: Must grant ALL privileges on tables, sequences, and functions, not just database.

7. **Network Order**: Guacamole must be on same network as PostgreSQL and guacd.

8. **Simple is Better**: File-based auth (user-mapping.xml) works instantly without database complexity for testing.

## Deployment Steps

1. **Initialize database** (if not already done):
   ```bash
   ./initdatabase.sh
   ```

2. **Deploy Guacamole**:
   ```bash
   ./deploy.sh
   ```

3. **Access**: https://guacamole.ai-servicers.com/
   - Username: guacadmin
   - Password: guacadmin

---
*Created: 2025-01-26 by Claude*
*Last Updated: 2025-01-26 - Final production configuration with security review*