# Laravel + Dokploy Demo

Aplicação Laravel containerizada com [FrankenPHP](https://frankenphp.dev/) (Caddy embutido),
pronta para rodar localmente via Docker Compose e para deploy no
[Dokploy](https://dokploy.com/) com **Docker Swarm**.

## Stack

- **Laravel** (PHP 8.x)
- **FrankenPHP** servindo a aplicação na porta `8001` (config no `Caddyfile`)
- **PostgreSQL 16** como banco de dados, persistido em volume Docker
- **MinIO** como storage de arquivos (S3-compatível), persistido em volume Docker
- **Traefik v3** como reverse proxy com load balancing HTTP por requisição
- **traefik-manager** como UI web para gerenciar rotas e middlewares do Traefik
- **Docker / Docker Compose** para build e execução local
- **Dokploy + Docker Swarm** para deploy remoto

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│            MÁQUINA MANAGER (Dokploy)            │
│                                                 │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐      │
│  │ Dokploy │  │  Builder │  │ Registry  │      │
│  │  (UI)   │→ │ (build)  │→ │:5000(local│      │
│  └─────────┘  └──────────┘  └─────┬─────┘      │
│                                   │            │
│  ┌──────────────────────────────────────────┐  │
│  │           Docker Swarm Manager           │  │
│  └────────────────────┬─────────────────────┘  │
│                       │ docker stack deploy     │
│  ┌────────────────────▼─────────────────────┐  │
│  │  Traefik :80  ←  load balancer HTTP      │  │
│  │  traefik-manager :5000  ←  UI de rotas   │  │
│  └────────────────────┬─────────────────────┘  │
└───────────────────────┼─────────────────────────┘
                        │ round-robin por requisição
         ┌──────────────┼──────────────┐
         │              │              │
    ┌────▼───┐     ┌────▼───┐     ┌───▼────┐
    │ app.1  │     │ app.2  │     │ app.3  │
    │ :8001  │     │ :8001  │     │ :8001  │
    └────────┘     └────────┘     └────────┘
         │              │              │
    ┌────▼──────────────▼──────────────▼────┐
    │        postgres    minio              │
    └───────────────────────────────────────┘
```

**Fluxo de deploy:**
1. Dokploy clona o repositório no manager
2. Builda a imagem a partir do `Dockerfile`
3. Faz push para o registry local (`localhost:5000`) — sem necessidade de registry externo
4. Executa `docker stack deploy` — o Swarm distribui os containers nos nós
5. O `entrypoint.sh` aguarda o PostgreSQL subir, roda as migrations e o `optimize`

> **Nó único:** Todos os serviços rodam no mesmo servidor. Funciona perfeitamente para ambientes pequenos e médios.

## Serviços

| Serviço | Imagem | Porta | Finalidade |
|---|---|---|---|
| `traefik` | `traefik:v3.6` | `80` (HTTP), `8080` (Dashboard) | Reverse proxy + load balancer |
| `traefik-manager` | `ghcr.io/chr0nzz/traefik-manager` | `8090` | UI para gerenciar rotas e middlewares |
| `app` | Build do `Dockerfile` | `8001` (direto), `80` (via Traefik) | Aplicação Laravel (FrankenPHP) |
| `postgres` | `postgres:16-alpine` | interno | Banco de dados |
| `minio` | `minio/minio:latest` | `9000` (API), `9001` (Console) | Storage S3-compatível |
| `minio-init` | `minio/mc:latest` | — | Cria o bucket na primeira vez |

## Requisitos

- Docker e Docker Compose instalados
- **Não** é necessário ter PHP nem Composer instalados localmente — tudo roda dentro do container

## Sobre o `APP_KEY`

A aplicação **não gera** o `APP_KEY` automaticamente: ele precisa ser fornecido como
variável de ambiente **antes** do container subir.

- O Laravel lê a chave em `config/app.php` via `env('APP_KEY')` (sem valor padrão)
- O `docker-compose.yml` repassa essa variável com `APP_KEY: ${APP_KEY}`
- O `docker/entrypoint.sh` **não** executa `php artisan key:generate`

Se a chave estiver vazia, o Laravel falha com `No application encryption key has been specified`.
Use **a mesma chave** em todos os ambientes e mantenha-a fixa entre deploys.

### Gerar o `APP_KEY` (sem PHP local)

```bash
# Recomendado: imagem oficial do PHP
docker run --rm php:8.3-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"

# Usando o artisan do próprio projeto (precisa da imagem buildada)
docker compose build
docker compose run --rm --entrypoint php app artisan key:generate --show
```

> O `--entrypoint php` pula o `entrypoint.sh`; sem isso ele tentaria rodar migrations/optimize sem `APP_KEY`.

## Rodando localmente (Docker Compose)

1. Crie o arquivo `.env` a partir do exemplo:

   ```bash
   cp .env.example .env
   ```

2. Defina as variáveis obrigatórias:

   ```bash
   # APP_KEY
   sed -i "s|^APP_KEY=.*|APP_KEY=base64:SUA_CHAVE_AQUI|" .env

   # Senha do banco (escolha uma senha forte)
   sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=sua_senha_postgres|" .env

   # URL local
   sed -i "s|^APP_URL=.*|APP_URL=http://localhost:8001|" .env
   ```

3. Suba todos os serviços (app + postgres + minio + traefik + traefik-manager):

   ```bash
   docker compose up -d --build
   ```

4. Acesse:
   - Aplicação via Traefik (load balancing por requisição): <http://localhost>
   - Aplicação direta (sem proxy): <http://localhost:8001>
   - Traefik Dashboard: <http://localhost:8080>
   - traefik-manager: <http://localhost:8090> (senha: `admin`)
   - MinIO Console: <http://localhost:9001> (usuário: `minioadmin` / senha: `minioadmin`)

Comandos úteis:

```bash
docker compose logs -f app       # logs da aplicação
docker compose logs -f postgres  # logs do banco
docker compose down              # parar e remover containers
docker compose down -v           # parar e remover containers + volumes (apaga dados!)
```

No boot, o `entrypoint.sh` aguarda o PostgreSQL ficar disponível, roda as migrations (`migrate --force`) e o `optimize`.

## Deploy no Dokploy com Docker Swarm

### Pré-requisitos no servidor

- Dokploy instalado no nó manager
- Swarm inicializado (o Dokploy faz isso automaticamente na instalação)
- Workers adicionados ao Swarm via Dokploy (opcional para nó único)

### Passo a passo

1. **Envie o projeto para um repositório Git** (GitHub, GitLab, etc.)

2. **No Dokploy**, crie um novo serviço do tipo **Docker Compose** apontando para o repositório

3. Na aba **Environment**, defina as variáveis. No mínimo:

   ```env
   # Obrigatórias
   APP_KEY=base64:SUA_CHAVE_AQUI
   APP_URL=https://seu-dominio.com
   DB_PASSWORD=senha_forte_aqui

   # Opcionais (já possuem padrão)
   DB_DATABASE=laravel
   DB_USERNAME=laravel
   MINIO_ROOT_USER=minioadmin
   MINIO_ROOT_PASSWORD=senha_minio_aqui
   MINIO_BUCKET=laravel
   TRUSTED_PROXIES=*
   ```

4. Configure o **domínio** apontando para a porta **`80`** (Traefik)

   > Em produção o Traefik recebe na porta 80/443 e distribui as requisições entre as réplicas do `app`. Configure `APP_DOMAIN` com o domínio real para que o roteamento Traefik funcione:
   >
   > ```env
   > APP_DOMAIN=meuapp.exemplo.com
   > ```

5. Clique em **Deploy**

   O Dokploy irá:
   - Buildar a imagem no servidor (sem necessidade de registry externo)
   - Fazer push para o registry local (`:5000`)
   - Executar `docker stack deploy` com todos os serviços
   - O `entrypoint.sh` aguardará o PostgreSQL, rodará as migrations e o `optimize`

### Volumes e persistência no Swarm

| Volume | Conteúdo | Observação |
|---|---|---|
| `postgres_data` | Dados do banco | Fixo no manager via placement constraint |
| `minio_data` | Arquivos (uploads) | Fixo no manager via placement constraint |
| `laravel_storage` | Cache de framework | Recriado automaticamente no boot |
| `traefik_dynamic` | `dynamic.yml` gerenciado pelo traefik-manager | Compartilhado entre `traefik` e `traefik-manager` |
| `traefik_logs` | Access logs do Traefik | Opcional, para debug |

> **Importante em multi-nó:** Volumes locais não são compartilhados entre nós. Para garantir que `postgres` e `minio` sempre rodem no mesmo nó (com seus dados), configure constraints de placement no Dokploy ou no `docker-compose.yml`:
>
> ```yaml
> deploy:
>   placement:
>     constraints:
>       - node.role == manager
> ```

### Verificar o status do deploy

```bash
# No servidor (via SSH)
docker stack ps <nome-do-stack>
docker service logs <nome-do-stack>_app
docker service logs <nome-do-stack>_postgres
```

## Testando com Docker Swarm localmente

Para simular exatamente o ambiente do Dokploy na sua máquina:

### 1. Inicializar o Swarm e o registry local

```bash
# Inicializar o Swarm (só na primeira vez)
docker swarm init

# Subir o registry local na porta 5000 (equivalente ao do Dokploy)
docker run -d -p 5000:5000 --name registry --restart=always registry:2
```

### 2. Buildar e publicar a imagem

```bash
# Build e push para o registry local
docker build -t localhost:5000/laravel-app:latest .
docker push localhost:5000/laravel-app:latest
```

### 3. Fazer o deploy como stack

Exporte as variáveis obrigatórias e faça o deploy com o `docker-stack.yml` (já inclui Traefik, traefik-manager, PostgreSQL e MinIO):

```bash
export APP_KEY=base64:SUA_CHAVE_AQUI
export DB_PASSWORD=sua_senha

docker stack deploy -c docker-stack.yml laravel-demo
```

Acesse após o deploy:

| URL | Serviço |
|---|---|
| <http://localhost> | Aplicação via Traefik |
| <http://localhost:8001> | Aplicação direta (sem proxy) |
| <http://localhost:8080> | Traefik Dashboard |
| <http://localhost:8090> | traefik-manager UI (senha: `admin`) |
| <http://localhost:9001> | MinIO Console (minioadmin/minioadmin) |

> **Nota:** A porta `8090` é usada para o traefik-manager porque `5000` já está ocupada pelo registry local.

### 4. Verificar o status

```bash
# Ver todos os serviços do stack
docker stack ps laravel-demo

# Ver logs do app
docker service logs laravel-demo_app

# Ver logs do postgres
docker service logs laravel-demo_postgres
```

### 5. Escalar o app

```bash
# Escalar para 3 réplicas
docker service scale laravel-demo_app=3

# Verificar as réplicas rodando
docker stack ps laravel-demo --filter "name=laravel-demo_app"
```

### 6. Verificar o load balancing

O Traefik roteia `localhost:80` → Swarm VIP `app:8001` → as 3 réplicas via IPVS (LB por conexão). Para ver o round-robin por conexão, use a porta direta:

```bash
# Porta 8001 (sem Traefik) — demonstra round-robin entre réplicas
for i in $(seq 1 9); do
  curl -sL http://localhost:8001/files | grep -o 'font-bold">[^<]*' | sed 's/font-bold">//'
done
# Resultado esperado: os 3 containers alternando
```

Através do Traefik na porta 80, o ráfego passa pelo Swarm VIP que faz IPVS connection-level load balancing. O container mostrado pode ser sempre o mesmo numa sessão, mas **muda entre sessões diferentes**.

### traefik-manager

Acesse <http://localhost:8090> para gerenciar rotas e middlewares via UI:

| Campo | Valor |
|---|---|
| URL | <http://localhost:8090> |
| Usuário | `admin` |
| Senha | `admin` |

> A senha padrão é `admin` definida via `ADMIN_PASSWORD: ${TM_PASSWORD:-admin}` no `docker-stack.yml`.
> Para alterar, exporte `TM_PASSWORD=sua_senha` antes do deploy.

```bash
# Verificar status e rotas ativas
curl -s http://localhost:8080/api/http/routers | python3 -m json.tool | grep -E '"name"|"rule"|"status"'
```

Na UI do traefik-manager você pode:
- Ver todas as rotas ativas (`laravel@file` → `Host(localhost)`)
- Adicionar middlewares (rate limit, auth, CORS, headers) sem editar YAML
- Monitorar saúde dos backends em tempo real
- Fazer backup e restaurar configurações

### 7. Deploy e rollback com versionamento por Git SHA

Os scripts em `scripts/` automatizam o fluxo completo com tag por commit:

```bash
# Deploy: build + tag (git SHA) + push + rolling update
sh scripts/deploy.sh

# Ver tags disponíveis no registry
sh scripts/rollback.sh --list

# Rollback automático (volta para a versão anterior do Swarm)
sh scripts/rollback.sh

# Rollback para uma tag específica
sh scripts/rollback.sh abc1234
```

Cada deploy gera duas tags no registry:

```
localhost:5000/laravel-app:abc1234   ← imutável (git SHA)
localhost:5000/laravel-app:latest    ← aponta para o mais recente
```

Isso permite reverter para qualquer versão anterior com precisão — o mesmo mecanismo que o Dokploy usa na aba **Deployments**.

### 8. Derrubar tudo

```bash
# Remover o stack (para e remove todos os containers do stack)
docker stack rm laravel-demo

# Opcional: sair do Swarm e remover o registry local
docker swarm leave --force
docker rm -f registry
```

## Variáveis de ambiente

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `APP_KEY` | **Sim** | — | Chave de criptografia (`base64:...`) |
| `APP_URL` | **Sim** | `http://localhost:8001` | URL pública da aplicação |
| `DB_PASSWORD` | **Sim** | — | Senha do PostgreSQL |
| `APP_ENV` | Não | `production` | Ambiente Laravel |
| `APP_DEBUG` | Não | `false` | Debug mode |
| `DB_DATABASE` | Não | `laravel` | Nome do banco |
| `DB_USERNAME` | Não | `laravel` | Usuário do banco |
| `MINIO_ROOT_USER` | Não | `minioadmin` | Usuário admin do MinIO |
| `MINIO_ROOT_PASSWORD` | Não | `minioadmin` | Senha admin do MinIO |
| `MINIO_BUCKET` | Não | `laravel` | Nome do bucket padrão |
| `TRUSTED_PROXIES` | Não | `*` | Proxies confiáveis |
| `APP_DOMAIN` | Não | `localhost` | Domínio configurado no Traefik para roteamento |
| `TM_PASSWORD` | Não | `admin` | Senha do traefik-manager (acesso em `:8090`) |
