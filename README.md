# Laravel Dokploy Demo

Este laboratorio simula localmente uma arquitetura parecida com um deploy feito pelo Dokploy: a aplicacao Laravel roda em replicas no Docker Swarm, o Traefik faz o roteamento HTTPS, um registry local distribui a imagem da app para o cluster, e os estados compartilhados ficam fora dos containers da aplicacao.

A ideia principal e evitar que a aplicacao dependa de SQLite, uploads locais ou sessoes em disco quando estiver escalada. Para isso, a stack usa Postgres, Redis e MinIO.

## Arquitetura

Fluxo de requisicao e dependencias:

```text
Browser
  |
  | HTTPS :443
  v
Traefik
  |-- HTTP :80 -> HTTPS redirect
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

- `traefik`: reverse proxy HTTPS da stack. Le labels dos servicos Swarm, publica as rotas e redireciona HTTP para HTTPS.
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
- `docker/traefik/dynamic/tls.yml`: configuracao dinamica do Traefik para carregar o certificado TLS local.
- `scripts/generate-local-tls.sh`: gera o certificado self-signed local usado pelo Traefik.
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

Gere, tagueie e publique a imagem no registry local. Para permitir rollback, use uma tag imutavel por deploy e mantenha `current` apenas como ponteiro para a ultima imagem publicada:

```bash
export DEPLOY_TAG="$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"

docker build -t laravel-dokploy-demo:${DEPLOY_TAG} .
docker tag laravel-dokploy-demo:${DEPLOY_TAG} localhost:5000/laravel-dokploy-demo:${DEPLOY_TAG}
docker tag laravel-dokploy-demo:${DEPLOY_TAG} localhost:5000/laravel-dokploy-demo:current

docker push localhost:5000/laravel-dokploy-demo:${DEPLOY_TAG}
docker push localhost:5000/laravel-dokploy-demo:current
```

Defina a `APP_KEY` que sera injetada nos servicos da stack, tambem sem depender do PHP local:

```bash
export APP_KEY="$(docker compose -f docker-compose.commands.yml run --rm php php -r 'echo "base64:".base64_encode(random_bytes(32)).PHP_EOL;')"
```

Por padrao, `docker-stack.local.yml` usa `APP_IMAGE=localhost:5000/laravel-dokploy-demo:current`. Para deploys rastreaveis e com rollback, prefira fixar a tag imutavel gerada no build:

```bash
export APP_IMAGE=localhost:5000/laravel-dokploy-demo:${DEPLOY_TAG}
```

### Certificado HTTPS Local

A stack usa HTTPS pelo Traefik com um certificado self-signed local. Gere o certificado antes de publicar a stack da aplicacao:

```bash
./scripts/generate-local-tls.sh
```

O script cria os arquivos ignorados pelo Git em:

```text
docker/traefik/certs/local.crt
docker/traefik/certs/local.key
```

O certificado inclui SANs para `laravel.localhost`, `manager.localhost`, `minio.localhost`, `minio-console.localhost`, `localhost` e `127.0.0.1`. Como ele e self-signed, o navegador deve exibir um aviso de certificado nao confiavel. Para testes por linha de comando, use `curl -k`.

### Estrategia De Tags E Rollback

A stack usa duas categorias de tags:

- Tag imutavel de deploy: `YYYYmmddHHMMSS-<git-sha-curto>`, por exemplo `20260625141030-1a2b3c4`.
- Tag movel: `current`, usada apenas como referencia rapida para a ultima imagem publicada.

Em producao, evite fazer deploy por `current`, porque ela muda com o tempo. Para reproduzir ou reverter uma versao, use sempre uma tag imutavel.

Para ver qual imagem esta rodando no servico da aplicacao:

```bash
docker service inspect laravel-demo_app --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
```

Para listar as tags armazenadas no registry local:

```bash
curl http://localhost:5000/v2/laravel-dokploy-demo/tags/list
```

Para fazer rollback, escolha uma tag anterior e reaplique a stack com `APP_IMAGE` apontando para ela:

```bash
export APP_IMAGE=localhost:5000/laravel-dokploy-demo:TAG_ANTERIOR
docker stack deploy -c docker-stack.local.yml laravel-demo
```

Rollback de imagem nao desfaz migracoes de banco. Se uma versao aplicou migracoes destrutivas, restaure o banco a partir de backup antes de voltar a imagem.

### Teste Visual De Replica

As paginas de listagem e upload mostram o hostname do container que atendeu a requisicao:

```text
https://laravel.localhost/files
https://laravel.localhost/files/create
```

Com mais de uma replica da aplicacao, recarregue a pagina algumas vezes e observe o valor `Container`. Ele ajuda a validar se o Traefik esta distribuindo as requisicoes entre replicas diferentes apos um novo deploy ou rollback.

### Deploy Da Stack

Publique a stack:

```bash
docker stack deploy -c docker-stack.local.yml laravel-demo
```

Servicos expostos pelo Traefik:

- Aplicacao Laravel: `https://laravel.localhost`
- Traefik dashboard: `http://localhost:8080`
- Traefik Manager: `https://manager.localhost`
- MinIO API: `https://minio.localhost`
- MinIO console: `https://minio-console.localhost`

Valide o HTTPS e o redirecionamento HTTP:

```bash
curl -k https://laravel.localhost
curl -I http://laravel.localhost
```

### Acesso Ao Traefik Manager

Abra o Traefik Manager em:

```text
https://manager.localhost
```

Na primeira inicializacao, o Traefik Manager gera uma senha temporaria nos logs do servico. Para consultar a senha atual:

```bash
docker service logs --tail 120 laravel-demo_traefik-manager | grep 'Password:'
```

Use a senha mais recente da task em execucao. Apos o primeiro login, a interface pode solicitar a definicao de uma senha permanente.

Nesta simulacao, o Traefik Manager e iniciado com um unico worker do Gunicorn. A imagem padrao usa dois workers, mas isso pode gerar uma condicao de corrida na criacao do arquivo `manager.yml` e deixar o servico em crash loop.

### Acesso Ao MinIO

O MinIO expõe a API S3 e o console web:

- API S3: `https://minio.localhost`
- Console web: `https://minio-console.localhost`

Credenciais padrao da stack:

```text
Usuario: minioadmin
Senha: minioadmin
```

A aplicacao usa o bucket `laravel-demo`. Se o job `laravel-demo_minio-create-bucket` nao tiver completado, crie esse bucket manualmente pelo console ou reaplique a stack corrigida.

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
