# Apache Guacamole - Remote Access Gateway

Apache Guacamole provides clientless remote desktop access via web browser.

## Quick Start

```bash
# Initialize database (first time only)
./initdatabase.sh

# Deploy Guacamole
./deploy.sh
```

## Access

- **URL**: https://guacamole.ai-servicers.com/
- **Username**: guacadmin
- **Password**: guacadmin

## Available Connections

- **Local SSH Server** - Terminal access
- **Local RDP Desktop** - Full graphical desktop

## Scripts

- `deploy.sh` - Deploy/restart Guacamole with Traefik
- `initdatabase.sh` - Initialize PostgreSQL database
- `add-connection.sh` - Add new SSH/RDP/VNC connections

## Documentation

See `CLAUDE.md` for detailed documentation and troubleshooting.