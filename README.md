# Leet-Jenkins

> GitHub-focused Jenkins — ephemeral, reproducible, secure.

## Features

- **GitHub-first** — Pre-configured GitHub PAT credential for repo access
- **Zero-touch setup** via Jenkins Configuration as Code (JCasC)
- **Ephemeral Docker agents** via Docker-in-Docker (isolated builds)
- **Security hardened** (no setup wizard, CSRF protection, disabled legacy protocols)
- **Minimal plugin set** — Only what's needed, nothing extra
- **Fully reproducible** — `docker compose down -v && up -d` resets everything

## Quick Start

```bash
# Start Jenkins
docker compose up -d

# View logs
docker compose logs -f jenkins

# Access UI
open http://localhost:8080
```

**Default credentials:** `admin` / `admin`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose Network                    │
├──────────────────────────┬──────────────────────────────────┤
│                          │                                   │
│   ┌──────────────────┐   │   ┌────────────────────────────┐ │
│   │                  │   │   │                            │ │
│   │  Jenkins         │◄──┼───│  Docker-in-Docker (DinD)   │ │
│   │  Controller      │   │   │                            │ │
│   │                  │   │   │  - Ephemeral agents        │ │
│   │  - JCasC config  │   │   │  - Isolated Docker daemon  │ │
│   │  - Plugin mgmt   │   │   │  - TLS encrypted           │ │
│   │  - Web UI :8080  │   │   │                            │ │
│   │  - Agent :50000  │   │   └────────────────────────────┘ │
│   │                  │   │                                   │
│   └──────────────────┘   │                                   │
│                          │                                   │
└──────────────────────────┴───────────────────────────────────┘
```

## Commands

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start Jenkins |
| `docker compose down` | Stop Jenkins (preserves data) |
| `docker compose down -v` | Stop and **delete all data** |
| `docker compose logs -f jenkins` | Follow Jenkins logs |
| `docker compose exec jenkins bash` | Shell into Jenkins container |
| `docker compose restart jenkins` | Restart Jenkins |

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `GITHUB_TOKEN` | — | **Required.** GitHub PAT for repo access |
| `JENKINS_ADMIN_ID` | `admin` | Admin username |
| `JENKINS_ADMIN_PASSWORD` | `admin` | Admin password |
| `JENKINS_URL` | `http://localhost:8080` | External URL |
| `JENKINS_HTTP_PORT` | `8080` | Web UI port |
| `JENKINS_HEAP_MAX` | `2g` | Max JVM heap |

### Customizing JCasC

Edit `config/casc.yaml` to:
- Add users and permissions
- Configure credentials
- Define cloud agents
- Set up global tools
- Create seed jobs

Changes apply on restart: `docker compose restart jenkins`

### Adding Plugins

Edit `config/plugins.txt` and rebuild:

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

## Plugins

| Category | Plugins |
|----------|--------|
| Core | configuration-as-code, job-dsl |
| Pipeline | workflow-aggregator, pipeline-stage-view, pipeline-graph-view |
| GitHub | git, github, github-branch-source |
| Docker | docker-plugin, docker-workflow |
| Credentials | credentials, credentials-binding, plain-credentials, ssh-credentials |
| UI | dark-theme, ansicolor, timestamper |
| Utils | ws-cleanup, build-timeout, generic-webhook-trigger, junit |

## Security Best Practices

This setup implements:

1. **No setup wizard** — Configuration is declarative
2. **CSRF protection** — Enabled by default
3. **Disabled legacy protocols** — Only JNLP4 allowed
4. **No builds on controller** — Executors = 0
5. **Docker isolation** — Builds run in separate Docker daemon
6. **TLS encryption** — DinD communication is encrypted
7. **No new privileges** — Security option enabled

## Backup & Restore

### Backup

```bash
# Backup Jenkins home
docker run --rm -v jenkins_home:/data -v $(pwd):/backup \
  alpine tar czf /backup/jenkins_backup.tar.gz -C /data .
```

### Restore

```bash
# Restore Jenkins home
docker compose down
docker volume rm jenkins_home
docker volume create jenkins_home
docker run --rm -v jenkins_home:/data -v $(pwd):/backup \
  alpine tar xzf /backup/jenkins_backup.tar.gz -C /data
docker compose up -d
```

## GitHub Credential

Your GitHub PAT is available in Jenkins as credential ID `github-token`.

Use in pipelines:

```groovy
pipeline {
  agent { label 'docker-agent' }
  stages {
    stage('Checkout') {
      steps {
        git url: 'https://github.com/user/repo.git',
            credentialsId: 'github-token',
            branch: 'main'
      }
    }
  }
}
```

## Troubleshooting

### Jenkins won't start

```bash
# Check logs
docker compose logs jenkins

# Check DinD is healthy
docker compose ps
```

### Agents not connecting

```bash
# Verify DinD is accessible
docker compose exec jenkins docker info

# Check certificates
docker compose exec jenkins ls -la /certs/client
```

### Reset everything

```bash
docker compose down -v
docker compose up -d
```

## License

MIT
