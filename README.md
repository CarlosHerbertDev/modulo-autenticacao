# modulo-autenticacao

API de autenticação em Laravel 12 / PHP 8.2, empacotada em Docker.

> Explicação detalhada de cada arquivo da infraestrutura, linha a linha, em [DOCKER.md](DOCKER.md).

## Ambiente local

```bash
docker compose up -d --build
docker compose exec php php artisan migrate
docker compose exec php php artisan storage:link
```

O entrypoint de desenvolvimento cuida sozinho do `composer install`, do `.env`
(copiado do `.env.example`) e do `php artisan key:generate` na primeira subida.

| Serviço      | URL                     |
| ------------ | ----------------------- |
| Aplicação    | http://localhost:8099   |
| phpMyAdmin   | http://localhost:8098   |
| MySQL (host) | `127.0.0.1:3310`        |

Container da aplicação: `autenticacao_backend`.

```bash
docker compose exec php bash
```

## Imagens Docker

O `Dockerfile` é multi-stage:

| Stage  | Uso                     | Porta | Código             |
| ------ | ----------------------- | ----- | ------------------ |
| `dev`  | `docker-compose.yml`    | 80    | bind mount `./src` |
| `prod` | Render / VPS            | `$PORT` (padrão 10000) | copiado na imagem |

`prod` é o último stage, então um `docker build .` sem `--target` gera a imagem
de produção — é disso que o Render depende, pois o `render.yaml` não tem campo
de build target.

## Deploy no Render

1. `New → Blueprint` apontando para este repositório (usa o `render.yaml`).
2. Preencher as variáveis marcadas como `sync: false` no painel:
   - `APP_KEY` — gerar com `php artisan key:generate --show` e colar com o prefixo `base64:`
   - `APP_URL` — a URL `.onrender.com` do serviço, após o primeiro deploy
   - `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` — MySQL externo
   - `MYSQL_ATTR_SSL_CA` — `/etc/ssl/certs/ca-certificates.crt` se o provedor exigir TLS
3. O entrypoint de produção roda `migrate --force` e os caches de config/rotas/views a cada boot.

O Render não oferece MySQL gerenciado (só Postgres e Key Value), então o banco
precisa vir de um provedor externo.

## Deploy em VPS

```bash
cp .env.deploy.example .env
docker compose -f docker-compose.prod.yml up -d --build
```

A aplicação sobe em `127.0.0.1:8099`, sem TLS — coloque um proxy reverso
(nginx, Caddy ou Traefik) na frente para terminar HTTPS.
