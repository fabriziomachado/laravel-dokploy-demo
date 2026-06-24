# Laravel + Dokploy Demo

Aplicação Laravel containerizada com [FrankenPHP](https://frankenphp.dev/) (Caddy embutido),
pronta para rodar localmente via Docker Compose e para deploy no
[Dokploy](https://dokploy.com/) com **Docker Swarm**.

## Stack

- **Laravel** (PHP 8.x)
- **FrankenPHP** servindo a aplicação na porta `8001` (config no `Caddyfile`)
- **PostgreSQL 16** como banco de dados, persistido em volume Docker
- **MinIO** como storage de arquivos (S3-compatível), persistido em volume Docker
- **Docker / Docker Compose** para build e execução local
- **Dokploy + Docker Swarm** para deploy remoto

## Arquitetura

```
┌─────────────────────────────────────────────┐
│           MÁQUINA MANAGER (Dokploy)         │
│                                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Dokploy │  │  Builder │  │ Registry  │  │
│  │  (UI)   │→ │ (build)  │→ │:5000(local│  │
│  └─────────┘  └──────────┘  └─────┬─────┘  │
│                                   │        │
│  ┌────────────────────────────────▼──────┐ │
│  │         Docker Swarm Manager          │ │
│  │    (orquestra todos os nós)           │ │
│  └────────────────────────────────┬──────┘ │
└───────────────────────────────────┼────────┘
                                    │ docker stack deploy
              ┌─────────────────────┼──────────────────────┐
              │                     │                      │
    ┌─────────▼──────┐   ┌──────────▼─────┐   ┌───────────▼────┐
    │  WORKER NODE 1 │   │  WORKER NODE 2 │   │  WORKER NODE 3 │
    │                │   │                │   │                │
    │  [app]         │   │  [app]         │   │  [postgres]    │
    │  [minio]       │   │                │   │                │
    └────────────────┘   └────────────────┘   └────────────────┘
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
| `app` | Build do `Dockerfile` | `8001` | Aplicação Laravel (FrankenPHP) |
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

3. Suba todos os serviços (app + postgres + minio):

   ```bash
   docker compose up -d --build
   ```

4. Acesse:
   - Aplicação: <http://localhost:8001>
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

4. Configure o **domínio** apontando para a porta **`8001`**

5. Clique em **Deploy**

   O Dokploy irá:
   - Buildar a imagem no servidor (sem necessidade de registry externo)
   - Fazer push para o registry local (`:5000`)
   - Executar `docker stack deploy` com todos os serviços
   - O `entrypoint.sh` aguardará o PostgreSQL, rodará as migrations e o `optimize`

### Volumes e persistência no Swarm

| Volume | Conteúdo | Observação |
|---|---|---|
| `postgres_data` | Dados do banco | Fica no nó onde o postgres está agendado |
| `minio_data` | Arquivos (uploads) | Fica no nó onde o minio está agendado |
| `laravel_storage` | Cache de framework | Recriado automaticamente no boot |

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

Crie um arquivo `docker-stack.yml` baseado no `docker-compose.yml`, substituindo `build: .` pela imagem do registry e adicionando as variáveis diretamente:

```bash
docker stack deploy -c docker-stack.yml laravel-demo
```

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

Acesse http://localhost:8001 e recarregue a página várias vezes — o identificador do container no topo da página muda conforme o Swarm distribui as requisições:

```bash
# Via curl: dispara 6 requisições e mostra qual container respondeu cada uma
for i in $(seq 1 6); do
  curl -sc /dev/null http://localhost:8001 | grep -o '[a-f0-9]\{12\}' | head -1
done
```

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
