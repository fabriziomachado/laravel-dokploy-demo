# Deploy no Dokploy

Arquitetura de CD com Docker Compose: **app** (FrankenPHP), **worker** (filas), **scheduler** e **migrate** (one-shot), todos a partir do mesmo `Dockerfile` multi-stage.

## Pré-requisitos

- Instância Dokploy configurada
- Repositório Git com a branch `feature/dokploy-cd-architecture`
- Domínio apontando para o servidor Dokploy (opcional para testes internos)

## 1. PostgreSQL

1. No projeto Dokploy: **Add Service** → **Database** → **PostgreSQL**
2. Anote o host interno (ex.: nome do serviço gerado pelo Dokploy), porta, usuário, senha e database
3. Aguarde o banco ficar **Running** antes do Compose

## 2. Compose stack

1. **Add Service** → **Compose**
2. **Source:** repositório Git
3. **Branch:** `feature/dokploy-cd-architecture`
4. **Compose path:** `docker-compose.dokploy.yml`
5. **Environment** (aba Environment):

```env
APP_KEY=base64:...              # php artisan key:generate --show
APP_ENV=production
APP_DEBUG=false
APP_URL=https://seu-dominio.com
TRUSTED_PROXIES=*

DB_CONNECTION=pgsql
DB_HOST=<host-interno-postgres>
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=<senha>

QUEUE_CONNECTION=database
CACHE_STORE=database
SESSION_DRIVER=database
FILESYSTEM_DISK=local
LOG_CHANNEL=stderr
LOG_LEVEL=info
```

6. Clique em **Deploy**

### Ordem de subida

```
migrate (exit 0) → app + worker + scheduler
```

O serviço `migrate` roda `php artisan migrate --force` uma vez por deploy. App, worker e scheduler só iniciam após sucesso.

## 3. Domínio (serviço app)

1. Aba **Domains** → **Add Domain**
2. Serviço: `app`
3. Host: `seu-dominio.com`
4. Porta interna: `8001`

O Dokploy injeta labels Traefik automaticamente. Não exponha portas fixas no host no compose de produção.

## 4. Auto Deploy (CD)

1. Aba **Deployments** → conectar GitHub/GitLab/Gitea
2. Ativar **Auto Deploy on Push** na branch desejada
3. Cada push rebuilda as imagens e reexecuta `migrate` antes de subir os demais serviços

## 5. Monitoramento no console

| Serviço    | Função                          | Onde verificar        |
|------------|----------------------------------|------------------------|
| `migrate`  | Migrations one-shot              | Logs (deve exit 0)     |
| `app`      | HTTP FrankenPHP                  | Domínio, `/up`         |
| `worker`   | `queue:work`                     | Logs do worker         |
| `scheduler`| `schedule:work`                  | Logs (heartbeat/min)   |

- **Logs:** filtrados por serviço no painel Compose
- **Terminal:** shell em qualquer container (`php artisan tinker`, etc.)
- **Volume:** `laravel_storage` — uploads em `storage/app`

## 6. Validação pós-deploy

1. Logs do `migrate` sem erro
2. `GET https://seu-dominio.com/up` → 200
3. Upload em `/files` funciona
4. Logs do `scheduler` mostram `Scheduler heartbeat` a cada minuto
5. Badge de container em `/files` exibe hostname do pod `app`

## Desenvolvimento local

Stack simplificado com SQLite:

```bash
cp .env.example .env
php artisan key:generate   # copie APP_KEY para o ambiente
docker compose up --build
```

Usa `docker-compose.yml` (migrate + app, SQLite em volume).

## Estrutura Docker

```
Dockerfile
├── stage base   → FrankenPHP + extensões + composer
├── target app   → frankenphp run (HTTP :8001)
└── target worker → php artisan ... (queue / schedule / migrate)
```

Entrypoints:

- `docker/entrypoint-app.sh` — `optimize` condicional (`RUN_OPTIMIZE=true`), sem migrate
- `docker/entrypoint-worker.sh` — bootstrap SQLite local se necessário, `exec "$@"`

## Migrations manuais (fallback)

Se precisar rodar migrate fora do deploy:

1. **Schedule Task** no Dokploy → Compose → container `worker`
2. Comando: `php artisan migrate --force`

Ou via terminal do serviço `worker` no painel.
