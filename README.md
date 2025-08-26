# Apache Guacamole - Remote Access Gateway

Apache Guacamole with Keycloak SSO integration for clientless remote desktop access.

## Quick Start

```bash
# Initialize database (first time only)
./initdatabase.sh

# Deploy Guacamole with SSO
./deploy.sh
```

## Access

- **URL**: https://guacamole.ai-servicers.com/
- **SSO**: Redirects to Keycloak for authentication
- **Fallback**: guacadmin/guacadmin (database auth)

## Authentication

1. **Primary**: Keycloak SSO
   - Users automatically provisioned on first login
   - Users in 'administrators' group get admin access

2. **Fallback**: Database authentication
   - Username: guacadmin
   - Password: guacadmin

## Available Connections

- **Local SSH Server** - Terminal access
- **Local RDP Desktop** - Full graphical desktop

## Scripts

- `deploy.sh` - Deploy Guacamole with Keycloak SSO
- `initdatabase.sh` - Initialize PostgreSQL database
- `add-connection.sh` - Add new SSH/RDP/VNC connections
- `setup-keycloak-sso.sh` - Configure SSO settings
- `configure-keycloak-client.sh` - Auto-configure Keycloak client

## Keycloak Configuration

- **Client ID**: guacamole
- **Admin Group**: administrators
- **Realm**: master

## Documentation

See `CLAUDE.md` for detailed documentation and troubleshooting.