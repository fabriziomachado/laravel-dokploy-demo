# Laravel Dokploy Demo

Este laboratorio simula localmente uma arquitetura parecida com um deploy feito pelo Dokploy: a aplicacao Laravel roda em replicas no Docker Swarm, o Traefik faz o roteamento HTTP, um registry local distribui a imagem da app para o cluster, e os estados compartilhados ficam fora dos containers da aplicacao.

A ideia principal e evitar que a aplicacao dependa de SQLite, uploads locais ou sessoes em disco quando estiver escalada. Para isso, a stack usa Postgres, Redis e MinIO.

## Arquitetura

Fluxo de requisicao e dependencias:

```text
Browser
  |
  v
Traefik :80
  |
  v
Laravel app replicas
  |-- Postgres: dados relacionais
  |-- Redis: sessoes, cache e filas
  |-- MinIO: uploads via API S3

Traefik Manager -> Traefik API
Docker Swarm -> agenda e escala os servicos
Registry local -> armazena a imagem usada pelas replicas
```

Servicos principais:

- `traefik`: reverse proxy HTTP da stack. Le labels dos servicos Swarm e publica as rotas.
- `traefik-manager`: interface para visualizar e gerenciar o Traefik.
- `app`: replicas da aplicacao Laravel com FrankenPHP.
- `migrate`: job Swarm que roda `php artisan migrate --force` uma unica vez.
- `postgres`: banco relacional da aplicacao.
- `redis`: sessoes, cache e filas.
- `minio`: storage S3 local para uploads.
- `minio-create-bucket`: job que cria o bucket usado pela aplicacao.
- `registry`: registry Docker local em `localhost:5000`.

## Por Que Usar Registry Local

Em Docker Swarm, uma imagem criada apenas com `docker build` fica disponivel somente no daemon Docker da maquina onde o build foi executado. Quando o Swarm escala ou agenda replicas em outros nos, esses nos precisam puxar a imagem de algum registry.

O Dokploy normalmente resolve isso com um registry interno ou configurado. Aqui a simulacao usa `registry:2`, publicado em `localhost:5000`, para reproduzir o fluxo:

```text
docker build -> docker tag -> docker push -> docker stack deploy -> replicas puxam a imagem
```

Por padrao, a stack usa:

```text
localhost:5000/laravel-dokploy-demo:local
```

Esse valor pode ser sobrescrito com `APP_IMAGE`.

## Arquivos Da Simulacao

- `Dockerfile`: imagem de producao da app, com build Vite em multi-stage e extensoes PHP para Postgres/Redis.
- `docker/entrypoint.sh`: prepara cache Laravel e permite desligar migracoes por replica com `RUN_MIGRATIONS=false`.
- `docker-stack.registry.yml`: registry local usado pelo Swarm.
- `docker-stack.local.yml`: stack Swarm da aplicacao e servicos auxiliares.
- `docker-compose.commands.yml`: runners para Composer, Artisan e Node sem depender do SO local.
- `docker/php-cli/Dockerfile`: imagem CLI para comandos de desenvolvimento e teste.

## Comandos Sem PHP/Node Local

Use `docker-compose.commands.yml` para rodar Composer, Artisan, testes e build frontend sem depender das instalacoes de PHP, Composer ou Node do SO local:

```bash
docker compose -f docker-compose.commands.yml run --rm composer install
docker compose -f docker-compose.commands.yml run --rm node npm ci
docker compose -f docker-compose.commands.yml run --rm node npm run build
docker compose -f docker-compose.commands.yml run --rm artisan test
```

A unica dependencia local esperada para esse fluxo e o Docker com o plugin Compose.

## Subir A Simulacao

### Registry Local E Build Da Imagem

`docker stack deploy` nao executa `build`. Em Swarm, principalmente com mais de um no, as replicas precisam puxar a imagem de um registry acessivel pelo cluster. Esta simulacao usa um registry local em `localhost:5000`.

Inicialize o Swarm, se ainda nao estiver ativo:

```bash
docker swarm init
```

Suba o registry antes da aplicacao:

```bash
docker stack deploy -c docker-stack.registry.yml registry
```

Gere, tagueie e publique a imagem no registry local:

```bash
docker build -t laravel-dokploy-demo:local .
docker tag laravel-dokploy-demo:local localhost:5000/laravel-dokploy-demo:local
docker push localhost:5000/laravel-dokploy-demo:local
```

Defina a `APP_KEY` que sera injetada nos servicos da stack, tambem sem depender do PHP local:

```bash
export APP_KEY="$(docker compose -f docker-compose.commands.yml run --rm php php -r 'echo "base64:".base64_encode(random_bytes(32)).PHP_EOL;')"
```

Por padrao, `docker-stack.local.yml` usa `APP_IMAGE=localhost:5000/laravel-dokploy-demo:local`. Para usar outro registry ou outra tag:

```bash
export APP_IMAGE=localhost:5000/laravel-dokploy-demo:minha-tag
```

### Deploy Da Stack

Publique a stack:

```bash
docker stack deploy -c docker-stack.local.yml laravel-demo
```

Servicos expostos pelo Traefik:

- Aplicacao Laravel: `http://laravel.localhost`
- Traefik dashboard: `http://localhost:8080`
- Traefik Manager: `http://manager.localhost`
- MinIO API: `http://minio.localhost`
- MinIO console: `http://minio-console.localhost`

### Acesso Ao Traefik Manager

Abra o Traefik Manager em:

```text
http://manager.localhost
```

Na primeira inicializacao, o Traefik Manager gera uma senha temporaria nos logs do servico. Para consultar a senha atual:

```bash
docker service logs --tail 120 laravel-demo_traefik-manager | grep 'Password:'
```

Use a senha mais recente da task em execucao. Apos o primeiro login, a interface pode solicitar a definicao de uma senha permanente.

## Migracoes E Escala

As replicas da aplicacao sobem com `RUN_MIGRATIONS=false`. A stack define um servico `migrate` em modo `replicated-job`, com uma unica tarefa, para evitar que varias replicas executem `php artisan migrate --force` ao mesmo tempo.

Verifique os servicos:

```bash
docker stack services laravel-demo
docker service ps laravel-demo_migrate
```

Escale a aplicacao:

```bash
docker service scale laravel-demo_app=3
```

Valide que uploads, sessoes e cache continuam funcionando apos escalar. Nesta stack, uploads usam o disco `s3` com MinIO, sessoes/cache/filas usam Redis, e dados relacionais usam Postgres.

## Remover A Simulacao

```bash
docker stack rm laravel-demo
docker stack rm registry
```

Os volumes Docker de Postgres, Redis, MinIO e registry permanecem no host ate serem removidos manualmente.
