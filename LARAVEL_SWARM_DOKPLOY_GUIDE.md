# Guia Para Laravel Em Docker Swarm Com Traefik

Este guia resume como aplicar em outros projetos Laravel a mesma configuracao usada neste laboratorio: imagem Docker de producao, registry local, Docker Swarm, Traefik, Postgres, Redis e MinIO.

## Objetivo

Preparar uma aplicacao Laravel para rodar em multiplas replicas sem depender de estado local no container.

Pontos principais:

- Banco relacional fora do container da aplicacao: Postgres.
- Sessoes, cache e filas fora do container da aplicacao: Redis.
- Uploads fora do container da aplicacao: MinIO/S3.
- Roteamento HTTP por Traefik.
- Imagens versionadas por tags imutaveis para permitir rollback.
- Migracoes executadas por um job unico, nao por todas as replicas.

## Checklist De Preparacao Do Laravel

1. Configure variaveis de ambiente para producao:

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=http://seu-app.localhost
TRUSTED_PROXIES=*

DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_CLIENT=phpredis

SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis

FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=laravel-demo
AWS_ENDPOINT=http://minio:9000
AWS_URL=http://minio.localhost/laravel-demo
AWS_USE_PATH_STYLE_ENDPOINT=true
```

2. Instale o adapter S3 do Laravel/Flysystem:

```bash
composer require league/flysystem-aws-s3-v3
```

3. Garanta que uploads usem o disk padrao ou `s3` explicitamente:

```php
$path = $request->file('file')->store('uploads');
```

Com `FILESYSTEM_DISK=s3`, esse upload vai para o MinIO/S3.

4. Evite salvar sessoes, cache, filas ou uploads em disco local quando a app tiver mais de uma replica.

## Dockerfile Base

Use build multi-stage para compilar assets e depois montar a imagem PHP:

```dockerfile
FROM node:22-alpine AS assets

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY resources ./resources
COPY vite.config.js ./
RUN npm run build

FROM dunglas/frankenphp

RUN install-php-extensions \
    bcmath \
    ctype \
    fileinfo \
    intl \
    json \
    mbstring \
    pdo \
    pdo_pgsql \
    redis \
    tokenizer \
    xml \
    zip

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --no-scripts \
    --optimize-autoloader \
    --prefer-dist

COPY . /app
COPY --from=assets /app/public/build /app/public/build

RUN composer dump-autoload --no-dev --optimize \
    && php artisan package:discover --ansi

RUN mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/app/Caddyfile"]
```

## Entrypoint Da Aplicacao

As replicas da aplicacao nao devem rodar migracoes automaticamente. Use uma flag `RUN_MIGRATIONS` para permitir esse comportamento apenas quando fizer sentido.

```sh
#!/bin/sh
set -e

if [ "${DB_CONNECTION:-sqlite}" = "sqlite" ] && [ -n "${DB_DATABASE:-}" ] && [ ! -f "${DB_DATABASE}" ]; then
    echo "Creating database.sqlite..."
    mkdir -p "$(dirname "${DB_DATABASE}")"
    touch "${DB_DATABASE}"
fi

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    echo "Running migrations..."
    php artisan migrate --force
else
    echo "Skipping migrations. Run the migration service before scaling app replicas."
fi

echo "Caching configuration..."
php artisan optimize

exec "$@"
```

## Stack Swarm

Use servicos separados para app, migracao, Postgres, Redis, MinIO e criacao do bucket.

Regras importantes:

- `app` usa `RUN_MIGRATIONS=false`.
- `migrate` roda `php artisan migrate --force` como `replicated-job`.
- `app` e `migrate` usam a mesma `APP_IMAGE`.
- `app` fica nas redes `public` e `private`.
- bancos, Redis e jobs internos ficam na rede `private`.
- Traefik le labels dos servicos Swarm e publica apenas o que tiver `traefik.enable=true`.

Exemplo de imagem da app:

```yaml
app:
  image: ${APP_IMAGE:-localhost:5000/minha-app:current}
  environment:
    APP_ENV: production
    APP_DEBUG: "false"
    APP_URL: http://minha-app.localhost
    APP_KEY: ${APP_KEY:?Set APP_KEY before deploying the stack}
    TRUSTED_PROXIES: "*"
    RUN_MIGRATIONS: "false"
    DB_CONNECTION: pgsql
    DB_HOST: postgres
    REDIS_HOST: redis
    SESSION_DRIVER: redis
    CACHE_STORE: redis
    QUEUE_CONNECTION: redis
    FILESYSTEM_DISK: s3
    AWS_ENDPOINT: http://minio:9000
    AWS_USE_PATH_STYLE_ENDPOINT: "true"
  networks:
    - public
    - private
  deploy:
    replicas: 2
    update_config:
      order: start-first
    labels:
      traefik.enable: "true"
      traefik.http.routers.minha-app.rule: Host(`minha-app.localhost`)
      traefik.http.routers.minha-app.entrypoints: web
      traefik.http.routers.minha-app.service: minha-app
      traefik.http.services.minha-app.loadbalancer.server.port: "8001"
```

## Registry E Tags Para Rollback

Em Swarm, nao dependa de `docker build` local sem registry. O Swarm precisa puxar a imagem por uma referencia disponivel para os nos.

Use uma tag imutavel por deploy e uma tag movel `current`:

```bash
export DEPLOY_TAG="$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"

docker build -t minha-app:${DEPLOY_TAG} .
docker tag minha-app:${DEPLOY_TAG} localhost:5000/minha-app:${DEPLOY_TAG}
docker tag minha-app:${DEPLOY_TAG} localhost:5000/minha-app:current

docker push localhost:5000/minha-app:${DEPLOY_TAG}
docker push localhost:5000/minha-app:current
```

Faça deploy fixando a tag imutavel:

```bash
export APP_IMAGE=localhost:5000/minha-app:${DEPLOY_TAG}
docker stack deploy -c docker-stack.local.yml minha-stack
```

Para ver a imagem atual:

```bash
docker service inspect minha-stack_app --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
```

Para listar tags do registry:

```bash
curl http://localhost:5000/v2/minha-app/tags/list
```

Para rollback:

```bash
export APP_IMAGE=localhost:5000/minha-app:TAG_ANTERIOR
docker stack deploy -c docker-stack.local.yml minha-stack
```

Rollback de imagem nao desfaz migracoes. Se houve migracao destrutiva, restaure o banco a partir de backup antes de voltar a imagem.

## Validacao De Replicas

Para saber qual replica atendeu a requisicao, exiba o hostname do container em alguma tela simples:

```blade
<p class="text-xs text-gray-500">
    Container: <span class="font-mono">{{ gethostname() ?: 'unknown' }}</span>
</p>
```

Depois escale a app e recarregue a pagina algumas vezes:

```bash
docker service scale minha-stack_app=3
docker stack services minha-stack
```

Se o Traefik estiver balanceando, o valor de `Container` deve alternar entre replicas.

## MinIO

Crie o bucket com um job Swarm ou manualmente:

```yaml
minio-create-bucket:
  image: minio/mc:latest
  entrypoint: ["/bin/sh", "-c"]
  command:
    - >
      until mc alias set local http://minio:9000 minioadmin minioadmin; do sleep 2; done;
      mc mb --ignore-existing local/laravel-demo;
      mc anonymous set download local/laravel-demo
```

O formato `command` como lista com um unico item e importante para o `sh -c` receber todo o script como um unico argumento.

Para validar:

```bash
docker run --rm --entrypoint /bin/sh --network minha-stack_private minio/mc:latest -c \
  "mc alias set local http://minio:9000 minioadmin minioadmin >/dev/null && mc ls local"
```

## Traefik Manager

Se usar `ghcr.io/chr0nzz/traefik-manager:latest`, sobrescreva o comando para um unico worker:

```yaml
traefik-manager:
  image: ghcr.io/chr0nzz/traefik-manager:latest
  command:
    - gunicorn
    - --bind
    - 0.0.0.0:5000
    - --workers
    - "1"
    - --log-level
    - info
    - app:app
```

Para consultar a senha temporaria:

```bash
docker service logs --tail 120 minha-stack_traefik-manager | grep 'Password:'
```

Use a senha mais recente da task em execucao.

## Comandos Uteis

```bash
docker stack services minha-stack
docker service ps minha-stack_app --no-trunc
docker service ps minha-stack_migrate --no-trunc
docker service logs --tail 100 minha-stack_app
docker service inspect minha-stack_app --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
```

## Licoes Aprendidas

- Nao use SQLite, sessoes em arquivo, cache local ou uploads locais quando a app tiver multiplas replicas. Cada replica teria seu proprio disco e o comportamento ficaria inconsistente.
- Nao rode migracoes em todas as replicas. Use um job unico de migracao para evitar execucoes concorrentes de `php artisan migrate --force`.
- Nao confie em `docker build` local para Swarm. Publique a imagem em um registry e referencie a imagem por `APP_IMAGE`.
- Nao use apenas `latest`, `local` ou `current` para deploys que precisam de rollback. Use tag imutavel por deploy e reserve `current` como ponteiro auxiliar.
- Nao esqueca de criar o bucket do MinIO. A app pode estar corretamente configurada para `s3`, mas uploads vao falhar ou nao aparecer se o bucket nao existir.
- Ao usar `minio/mc` com shell, sobrescreva o entrypoint quando necessario. A imagem usa `mc` como entrypoint, entao `docker run minio/mc sh -c ...` nao funciona sem `--entrypoint /bin/sh`.
- Em `docker stack`/Compose, cuidado com `command: >` junto de `entrypoint: ["/bin/sh", "-c"]`. Se o comando for renderizado como varios argumentos, o shell recebe apenas o primeiro trecho e falha com erro de sintaxe. Prefira `command: ["> script inteiro"]` ou uma lista YAML com um unico item multiline.
- O Traefik Manager pode entrar em crash loop se iniciar com dois workers e ambos tentarem gravar `manager.yml`. Sobrescreva o comando para `gunicorn --workers 1`.
- Ao reaplicar `docker stack deploy`, garanta que `APP_KEY` e `APP_IMAGE` estejam definidos. Se `APP_KEY` mudar, usuarios podem perder sessoes/cookies criptografados.
- Rollback de imagem nao desfaz migracoes. Planeje backups e migracoes reversiveis antes de deploys com alteracoes destrutivas no banco.
- Durante rolling update com `order: start-first`, o Swarm pode mostrar temporariamente mais replicas do que o desejado, por exemplo `3/2`. Aguarde estabilizar antes de validar o resultado final.
- Para saber se a requisicao caiu em replicas diferentes, exiba temporariamente `gethostname()` em uma tela de diagnostico.
