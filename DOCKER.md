# Guia do Docker — dev e produção

Este documento explica, arquivo por arquivo e linha por linha, como o projeto é
empacotado e executado. A linguagem é propositalmente simples: se você nunca
mexeu com Docker, dá para acompanhar do começo ao fim.

## Índice

- [A ideia geral](#a-ideia-geral)
- [Como rodar em desenvolvimento](#como-rodar-em-desenvolvimento)
- [Como rodar em produção](#como-rodar-em-produção)
- [Mapa dos arquivos](#mapa-dos-arquivos)
- [`Dockerfile`](#dockerfile)
- [`docker-compose.yml`](#docker-composeyml)
- [`docker/entrypoint.dev.sh`](#dockerentrypointdevsh)
- [`docker/entrypoint.prod.sh`](#dockerentrypointprodsh)
- [`docker/000-default.conf`](#docker000-defaultconf)
- [`docker/apache-tuning.conf`](#dockerapache-tuningconf)
- [`docker/php.ini`](#dockerphpini)
- [`.dockerignore`](#dockerignore)
- [`render.yaml`](#renderyaml)
- [`docker-compose.prod.yml`](#docker-composeprodyml)
- [`.env.deploy.example`](#envdeployexample)
- [Alterações no código Laravel](#alterações-no-código-laravel)
- [Problemas comuns](#problemas-comuns)

---

## A ideia geral

Um **container** é um computador em miniatura, isolado, criado a partir de uma
receita. A receita se chama **imagem**, e o arquivo que descreve como montar a
imagem é o **Dockerfile**.

O desafio aqui é que desenvolvimento e produção querem coisas opostas:

| | Desenvolvimento | Produção |
| --- | --- | --- |
| Código | precisa mudar a cada arquivo salvo | fica congelado |
| De onde vem o código | da sua pasta `src/`, em tempo real | copiado para dentro da imagem |
| Velocidade | não importa muito | importa muito |
| Erros na tela | ajudam | vazam informação |
| Banco | MySQL local do compose | MySQL externo |

Resolvemos isso com **um único `Dockerfile` dividido em três partes**, chamadas
*stages*:

```
base  →  tudo que os dois ambientes compartilham (PHP, Apache, extensões)
 ├── dev   →  base + opcache relaxado + entrypoint de desenvolvimento
 └── prod  →  base + código copiado + dependências otimizadas + entrypoint de produção
```

Uma imagem é construída de cada vez. Você escolhe qual com `--target`.

---

## Como rodar em desenvolvimento

```bash
docker compose up -d --build
docker compose exec php php artisan migrate
docker compose exec php php artisan storage:link
```

Pronto. Na primeira subida o container cuida sozinho do `composer install`, de
criar o `.env` a partir do `.env.example` e de gerar a `APP_KEY`.

| Serviço | Endereço |
| --- | --- |
| Aplicação | http://localhost:8099 |
| phpMyAdmin | http://localhost:8098 |
| MySQL (de fora do Docker) | `127.0.0.1:3310` |

Comandos do dia a dia:

```bash
docker compose exec php bash                 # entrar no container
docker compose exec php php artisan migrate  # rodar migrations
docker compose logs -f php                   # acompanhar os logs
docker compose down                          # desligar tudo
```

Você **não** precisa reconstruir a imagem ao editar PHP — o código é lido direto
da sua pasta `src/`. Só rode `--build` de novo se mexer no `Dockerfile` ou nos
arquivos de `docker/`.

---

## Como rodar em produção

Há dois destinos suportados, e os dois usam o mesmo stage `prod`.

### Render

O Render lê o `render.yaml`, constrói o `Dockerfile` e sobe o container. Você
não roda nenhum comando — ele faz tudo a partir do repositório Git.

1. No painel: `New → Blueprint`, apontando para este repositório.
2. Preencher as variáveis marcadas como `sync: false` (veja a seção do `render.yaml`).
3. Dar deploy.

O banco precisa ser um **MySQL externo** (Aiven, Clever Cloud, Railway,
PlanetScale...), porque o Render só oferece Postgres e Key Value gerenciados.

### VPS

```bash
cp .env.deploy.example .env   # e preencher os valores
docker compose -f docker-compose.prod.yml up -d --build
```

Aqui o MySQL sobe junto, como container. A aplicação fica em `127.0.0.1:8099`,
**sem HTTPS** — você precisa de um proxy reverso (Caddy, nginx ou Traefik) na
frente para colocar o certificado.

---

## Mapa dos arquivos

| Arquivo | Serve para | Usado em |
| --- | --- | --- |
| `Dockerfile` | receita das imagens `dev` e `prod` | ambos |
| `docker-compose.yml` | orquestra app + MySQL + phpMyAdmin na sua máquina | dev |
| `docker-compose.prod.yml` | mesma ideia, mas para VPS | prod (VPS) |
| `render.yaml` | descreve o serviço para o Render | prod (Render) |
| `.dockerignore` | lista o que **não** entra na imagem | ambos |
| `.env.deploy.example` | modelo das senhas usadas na VPS | prod (VPS) |
| `docker/entrypoint.dev.sh` | o que roda ao ligar o container de dev | dev |
| `docker/entrypoint.prod.sh` | o que roda ao ligar o container de prod | prod |
| `docker/000-default.conf` | site do Apache (aponta para `public/`) | ambos |
| `docker/apache-tuning.conf` | ajustes gerais do Apache | ambos |
| `docker/php.ini` | limites do PHP (upload, memória, tempo) | ambos |

---

## `Dockerfile`

A receita das imagens. Três stages no mesmo arquivo.

### Stage `base` — a fundação

```dockerfile
FROM php:8.2-apache AS base
```
Partimos de uma imagem oficial que já traz PHP 8.2 e Apache configurados juntos.
`AS base` dá um nome a este trecho, para os outros dois poderem reaproveitá-lo.

Usamos `8.2` em vez de `8.2.18` (como era antes) para receber correções de
segurança do PHP automaticamente a cada rebuild. O `composer.json` exige `^8.2`,
então qualquer 8.2.x serve.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        unzip git zip \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libzip-dev \
```
Instala programas e bibliotecas do sistema Linux.
`unzip`, `git` e `zip` são usados pelo Composer para baixar pacotes.
As bibliotecas `lib*-dev` são o material bruto para compilar as extensões de
imagem do PHP (`gd`) e de compactação (`zip`) nas linhas seguintes.
`--no-install-recommends` evita instalar pacotes "sugeridos" que ninguém pediu,
deixando a imagem menor.

```dockerfile
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
```
Prepara a extensão `gd` (manipulação de imagens) dizendo quais formatos ela deve
suportar: fontes, JPEG e WebP. Sem isso, `gd` compila sem suporte a JPEG.

```dockerfile
    && docker-php-ext-install -j"$(nproc)" gd pdo pdo_mysql zip opcache bcmath \
```
Compila e ativa as extensões. O que cada uma faz:
- `gd` — redimensionar e gerar imagens (útil para avatares, por exemplo)
- `pdo` + `pdo_mysql` — **conversar com o MySQL**; sem isso o Laravel não conecta
- `zip` — o Composer usa para descompactar pacotes
- `opcache` — guarda o PHP já compilado na memória; deixa a aplicação bem mais rápida
- `bcmath` — contas com precisão alta, exigido por várias bibliotecas

`-j"$(nproc)"` compila usando todos os núcleos do processador, para ser rápido.

```dockerfile
    && rm -rf /var/lib/apt/lists/*
```
Apaga o cache de pacotes do Linux. Já não serve para nada e ocupa dezenas de MB.

Repare que tudo isso é **um único `RUN`** encadeado por `&&`. Cada `RUN` cria uma
camada na imagem; se fossem quatro `RUN`, o lixo apagado no último ainda estaria
guardado nas camadas anteriores.

```dockerfile
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
```
Pega o executável do Composer direto da imagem oficial dele.

O código antigo baixava com `curl | php` toda vez que o container era criado:
lento, dependia de internet no momento de ligar, e sem conferir integridade.
Agora vem pronto, de fonte versionada, e fica dentro da imagem.

```dockerfile
RUN a2enmod rewrite headers
```
Liga dois módulos do Apache.
`rewrite` é **obrigatório** para o Laravel: é ele que faz o `.htaccess` mandar
todas as URLs para o `index.php`. Sem ele, só a página inicial funciona e todo o
resto dá 404.
`headers` permite manipular cabeçalhos HTTP (útil para CORS mais adiante).

```dockerfile
COPY docker/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY docker/apache-tuning.conf /etc/apache2/conf-available/zz-tuning.conf
RUN a2enconf zz-tuning
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-app.ini
```
Coloca nossos arquivos de configuração nos lugares certos.

Antes esses arquivos eram "montados" de fora pelo `docker-compose.yml`, o que
funcionava só na sua máquina. Agora fazem parte da imagem e valem em qualquer
lugar.

O prefixo `zz-` nos nomes é um truque: o Apache e o PHP leem os arquivos de
configuração em ordem alfabética, então começar com `zz` garante que os nossos
sejam lidos por último e sobrescrevam os padrões.

```dockerfile
WORKDIR /var/www/html
```
Define a pasta padrão. Daqui em diante, todo comando roda a partir dela, e é
onde o Apache espera encontrar o site.

### Stage `dev` — desenvolvimento

```dockerfile
FROM base AS dev
```
Começa de onde o `base` parou.

```dockerfile
RUN printf "opcache.validate_timestamps=1\nopcache.revalidate_freq=0\n" \
        > /usr/local/etc/php/conf.d/zz-opcache-dev.ini
```
Ajusta o opcache para desenvolvimento.

O opcache guarda o PHP compilado na memória para não reler o arquivo toda vez.
Ótimo para velocidade, péssimo para quem está editando código.
`validate_timestamps=1` manda verificar se o arquivo mudou.
`revalidate_freq=0` manda verificar **a cada requisição** (o padrão é esperar
2 segundos).
Resultado: você salva o arquivo e a próxima requisição já reflete a mudança.

```dockerfile
COPY docker/entrypoint.dev.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
```
Copia o script de inicialização e o torna executável.

Repare que o arquivo de origem tem nome diferente (`entrypoint.dev.sh`) mas o
destino é sempre `entrypoint.sh`. Assim as duas imagens têm a mesma "porta de
entrada", cada uma com o conteúdo apropriado.

```dockerfile
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```
`EXPOSE 80` é documentação: avisa que o container atende na porta 80.
`ENTRYPOINT` define o comando que roda quando o container liga.

### Stage `prod` — produção

```dockerfile
FROM base AS prod
```

**A ordem importa muito aqui.** `prod` precisa ser o **último** stage do arquivo,
porque o Docker constrói o último quando ninguém pede um `--target` específico.
E o Render não tem como pedir: o `render.yaml` só aceita `dockerfilePath`,
`dockerContext` e `dockerCommand` — não existe campo de target. Se `dev`
estivesse por último, o Render subiria a imagem de desenvolvimento, sem código
nenhum dentro.

```dockerfile
RUN printf "opcache.validate_timestamps=0\nopcache.memory_consumption=192\nopcache.max_accelerated_files=20000\n" \
        > /usr/local/etc/php/conf.d/zz-opcache-prod.ini
```
O oposto do que fizemos em dev.
`validate_timestamps=0` — nunca verifica se o arquivo mudou. Em produção o
código está congelado dentro da imagem, então verificar é desperdício puro.
`memory_consumption=192` — 192 MB reservados para o código compilado.
`max_accelerated_files=20000` — o Laravel com o `vendor` tem muitos arquivos; o
padrão (10 mil) ficaria apertado e começaria a descartar código do cache.

```dockerfile
COPY src/composer.json src/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction
```
Aqui tem um truque de performance importante.

Copiamos **só** os dois arquivos que listam as dependências, antes de copiar o
código. O Docker guarda o resultado de cada passo e reaproveita enquanto a
entrada não mudar. Como `composer.json` e `composer.lock` mudam raramente, o
download das dependências (que demora) é reaproveitado quase sempre. Se
copiássemos tudo de uma vez, qualquer mudança em qualquer arquivo PHP
invalidaria o cache e refaria o download inteiro.

As flags:
- `--no-dev` — não instala PHPUnit, Faker, Pint e companhia. Produção não testa.
- `--no-scripts` — **obrigatório aqui.** O `composer.json` deste projeto roda
  `php artisan package:discover` depois de instalar, e o `artisan` ainda não foi
  copiado. Sem essa flag, o build quebra.
- `--no-autoloader` — adia a geração do autoload, que depende do código.
- `--prefer-dist` — baixa pacotes zipados em vez de clonar repositórios Git.
- `--no-interaction` — nunca faz perguntas; não há ninguém para responder.

```dockerfile
COPY src/ ./
```
Agora sim, o código da aplicação entra na imagem.

Essa linha é a diferença central entre os dois ambientes, e era exatamente o que
faltava no Dockerfile antigo — ele nunca copiava o código, porque em dev o
compose "emprestava" a pasta de fora. Em produção não existe pasta de fora.

```dockerfile
RUN mkdir -p storage/framework/cache/data storage/framework/sessions \
             storage/framework/views storage/logs storage/app/public \
```
Cria as pastas de trabalho do Laravel.

Isso não é precaução teórica: na primeira versão deste setup o build **quebrou**
com `View path not found`, porque o `.dockerignore` tinha removido a pasta
`storage/framework/views` e o `php artisan view:cache` não tinha onde escrever.
O `mkdir -p` garante que a árvore exista sempre. (`-p` cria os pais necessários
e não reclama se já existirem.)

```dockerfile
    && composer dump-autoload --no-dev --optimize --classmap-authoritative \
```
Gera o mapa de "qual classe está em qual arquivo".
`--optimize` monta a lista completa antecipadamente, em vez de procurar no disco
a cada classe.
`--classmap-authoritative` vai além: se a classe não está no mapa, nem procura.
Mais rápido, e seguro porque em produção nada é adicionado depois.

```dockerfile
    && php artisan package:discover --ansi \
```
O passo que pulamos com `--no-scripts` lá atrás. Agora o `artisan` existe, então
o Laravel pode registrar os service providers dos pacotes instalados.

```dockerfile
    && chown -R www-data:www-data storage bootstrap/cache
```
Dá a posse dessas duas pastas ao usuário do Apache.

São as únicas pastas em que o Laravel **escreve** (logs, cache, sessões, views
compiladas). Sem isso, a aplicação sobe e morre com erro de permissão na
primeira requisição.

Note que damos permissão só ao necessário. O código antigo fazia
`chmod -R 777` na árvore inteira, o que é bem mais permissivo do que precisa ser.

```dockerfile
COPY docker/entrypoint.prod.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 10000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```
Mesmo esquema do `dev`, com o script de produção. `10000` é a porta padrão do
Render.

---

## `docker-compose.yml`

O `docker-compose` sobe vários containers de uma vez e os conecta numa rede
privada. Este arquivo descreve o ambiente da sua máquina.

```yaml
services:

  php:
    build:
      context: .
      target: dev
```
`context: .` — a pasta raiz do projeto é o material disponível para o build.
`target: dev` — **constrói o stage `dev`**, e para por ali. É assim que o mesmo
`Dockerfile` serve os dois mundos.

```yaml
    container_name: autenticacao_backend
```
Nome fixo do container, para você digitar
`docker exec -it autenticacao_backend bash` sem precisar descobrir um nome
gerado automaticamente.

```yaml
    volumes:
      - ./src:/var/www/html
```
**A linha mais importante do desenvolvimento.** Liga a sua pasta `src/` à pasta
do site dentro do container. Não é cópia: é a mesma pasta vista dos dois lados.
Você salva no editor, o container enxerga na hora.

É também por isso que o stage `dev` não copia código algum — seria apagado por
essa montagem de qualquer forma.

```yaml
    ports:
      - "8099:80"
```
Liga a porta 8099 do seu computador à porta 80 do container. Por isso o endereço
é `localhost:8099`.

(O README antigo dizia 8070, que nunca respondeu — foi corrigido.)

```yaml
    depends_on:
      db:
        condition: service_healthy
```
Só liga o PHP **depois que o MySQL estiver realmente aceitando conexões**.

A versão antiga usava só `depends_on: - db`, que espera apenas o container
*iniciar* — e o MySQL leva de 10 a 20 segundos entre iniciar e aceitar
conexões. Com `condition: service_healthy`, o compose aguarda o healthcheck
definido abaixo passar.

```yaml
  db:
    image: mysql:8.0
```
MySQL pronto, sem build.

```yaml
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: modulo_autenticacao
      MYSQL_USER: modulo_autenticacao
      MYSQL_PASSWORD: 123
```
Na primeira vez que sobe, o MySQL cria o banco e o usuário com esses valores.
Senhas fracas aqui não são problema: isso nunca sai da sua máquina. Em produção
os valores vêm de outro lugar.

```yaml
    ports:
      - "3310:3306"
```
Expõe o MySQL em `127.0.0.1:3310` para você conectar com DBeaver, TablePlus ou
similar. É 3310 e não 3306 para não brigar com um MySQL instalado direto no seu
sistema.

```yaml
    volumes:
      - mysql_data:/var/lib/mysql
```
Guarda os dados do banco num volume com nome.

Antes essa linha não existia, e os dados iam para um volume **anônimo** — o
Docker descarta esses volumes ao recriar o serviço ou num `docker compose down -v`.
Na prática: você perdia o banco sem perceber. Com nome, ele sobrevive.

```yaml
      - ./mysql-init:/docker-entrypoint-initdb.d
```
Qualquer `.sql` colocado em `mysql-init/` roda automaticamente na primeira
inicialização do banco. A pasta está vazia hoje, mas serve para seeds iniciais.

```yaml
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-proot"]
      interval: 5s
      timeout: 5s
      retries: 20
```
Como o Docker descobre se o MySQL já está pronto: tenta um `ping` a cada 5
segundos, até 20 vezes (100 segundos no total). Quando responde, o container é
marcado como *healthy* e o PHP é liberado para subir.

```yaml
  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    environment:
      PMA_HOST: db
```
Interface web para o banco, em `localhost:8098`.
`PMA_HOST: db` funciona porque dentro da rede do compose cada serviço é
alcançável pelo próprio nome.

```yaml
volumes:
  mysql_data:
```
Declara o volume nomeado usado acima.

---

## `docker/entrypoint.dev.sh`

O script que roda toda vez que o container de desenvolvimento liga.

```bash
#!/bin/bash
set -e
```
`set -e` interrompe o script no primeiro comando que falhar. Sem isso, um erro
no meio passaria despercebido e o Apache subiria num estado quebrado.

```bash
if [ ! -f vendor/autoload.php ]; then
    composer install --no-interaction --prefer-dist
fi
```
Se as dependências não estiverem instaladas, instala.

Isso faz o projeto funcionar num clone limpo sem nenhum passo manual. E o `if`
garante que nas próximas subidas o comando é pulado, sem atrasar nada.

Aqui instalamos **com** as dependências de desenvolvimento (sem `--no-dev`),
porque você quer PHPUnit e Pint na sua máquina.

```bash
if [ ! -f .env ]; then
    cp .env.example .env
    php artisan key:generate
fi
```
Cria o `.env` a partir do modelo e gera a chave de criptografia.

O `.env` não vai para o Git (contém segredos), então num clone novo ele não
existe. Sem `APP_KEY`, o Laravel não sobe.

Isso só funciona porque o `.env.example` foi corrigido para apontar para o
MySQL do compose — ele vinha configurado para SQLite, o que geraria um ambiente
silenciosamente diferente do esperado.

```bash
chown -R www-data:www-data storage bootstrap/cache
```
Corrige a posse das pastas graváveis.

Necessário porque elas vêm da sua pasta `src/` pela montagem, com o dono do seu
usuário Linux, e o Apache roda como `www-data`.

```bash
php artisan config:clear
```
Apaga qualquer cache de configuração.

É o oposto exato do que a produção faz, e é de propósito. Se sobrar um
`bootstrap/cache/config.php` de alguma execução anterior, suas mudanças no
`.env` param de surtir efeito, e você perde tempo caçando um problema que não
existe. Como a pasta é montada da sua máquina, esse arquivo também bagunçaria o
`php artisan` rodado fora do container.

```bash
exec apache2-foreground
```
Entrega o controle ao Apache.

`exec` substitui o processo do script pelo do Apache, em vez de criar um filho.
Isso faz o Apache virar o processo principal (PID 1) do container, que é o que
recebe os sinais de parada — sem isso, `docker compose down` demoraria 10
segundos e mataria o processo à força.

**Não há `migrate` aqui, de propósito.** Em desenvolvimento você controla quando
o banco muda.

---

## `docker/entrypoint.prod.sh`

O script de produção, usado no Render e na VPS.

```bash
#!/bin/bash
set -e
```

```bash
: "${PORT:=10000}"
```
Se a variável `PORT` não existir, assume 10000.

Sintaxe estranha, função simples: os dois-pontos são um comando que não faz
nada, servindo só para a expansão `:=` acontecer.

```bash
sed -ri "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf
```
Reescreve a porta nos dois arquivos do Apache antes de ligá-lo.

**Por que isso existe:** o Render não deixa você escolher a porta. Ele injeta a
variável `PORT` e espera que a aplicação atenda nela. O Apache tem a porta
escrita em arquivo de configuração, não lê variável de ambiente — então
reescrevemos os arquivos na hora de subir.

São dois arquivos porque o Apache precisa concordar consigo mesmo: `ports.conf`
diz em qual porta *escutar*, e `000-default.conf` diz a qual porta aquele site
*responde*. Se divergirem, o Apache sobe mas não atende.

Testado com `PORT=8080`: o Apache passou a escutar em 8080 e respondeu 200.

```bash
for var in APP_KEY DB_CONNECTION DB_HOST DB_DATABASE DB_USERNAME; do
    if [ -z "${!var}" ]; then
        echo "ERRO: variavel de ambiente ${var} nao definida." >&2
        exit 1
    fi
done
```
Confere se as variáveis essenciais foram configuradas e aborta se faltar alguma.
(`${!var}` lê o valor da variável cujo *nome* está em `var`; `-z` testa se está
vazio; `>&2` manda a mensagem para a saída de erro.)

**Essa guarda nasceu de um problema real encontrado em teste.** Rodei a imagem
de produção sem nenhuma variável e ela **não falhou**: o `config/database.php`
do Laravel tem `env('DB_CONNECTION', 'sqlite')` como padrão, então a aplicação
criou um banco SQLite temporário e subiu normalmente.

Em produção isso seria grave. Um `DB_HOST` digitado errado não quebraria o
deploy — a aplicação pareceria funcionar e perderia todos os dados a cada
reinício, porque o SQLite ficaria no disco efêmero do container. É muito melhor
falhar alto, no segundo zero.

```bash
php artisan migrate --force --no-interaction
```
Aplica as migrations pendentes.

`--force` é obrigatório: com `APP_ENV=production` o Laravel pede confirmação
antes de mexer no banco, e não há ninguém no terminal para confirmar.

Como isso roda a cada boot, um deploy novo já sobe com o banco atualizado. Se um
dia você rodar mais de uma réplica, tire esta linha daqui e faça disso um passo
separado do deploy — várias réplicas migrando ao mesmo tempo competem pela mesma
tabela.

```bash
php artisan config:cache
php artisan route:cache
php artisan view:cache
```
Pré-compila configuração, rotas e templates num arquivo só cada.

Economiza bastante trabalho em cada requisição: sem isso o Laravel lê dezenas de
arquivos de config e registra todas as rotas do zero a cada acesso.

**Por que no boot e não no build:** `config:cache` congela os valores das
variáveis de ambiente no momento em que roda. Durante o build no Render, essas
variáveis não existem — ele guardaria valores vazios. No boot, elas já foram
injetadas.

```bash
exec apache2-foreground
```
Mesma lógica do script de dev.

---

## `docker/000-default.conf`

O "site" do Apache.

```apache
<VirtualHost *:80>
```
Abre a definição do site. A porta é reescrita pelo entrypoint em produção.

```apache
	DocumentRoot /var/www/html/public
```
**A linha mais importante do arquivo.** Aponta a raiz do site para `public/`, e
não para a pasta do projeto.

Isso é uma exigência de segurança do Laravel: só `public/` deve ser alcançável
pelo navegador. Se apontasse para `/var/www/html`, qualquer pessoa poderia
baixar o seu `.env` com todas as senhas acessando `seusite.com/.env`.

```apache
	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined
```
Onde gravar os logs.

Parece que vai escrever em arquivo, mas não: a imagem oficial do PHP já
transforma esses dois caminhos em atalhos para a saída do terminal. Os logs
aparecem direto no `docker compose logs` e no painel do Render. (Verificado:
`access.log -> /dev/stdout`, `error.log -> /dev/stderr`.)

```apache
    <Directory /var/www/html/public>
        AllowOverride All
        Require all granted
    </Directory>
```
`AllowOverride All` autoriza o `.htaccess` que vem dentro de `public/` a
funcionar — é ele que redireciona todas as URLs para o `index.php`. Sem essa
linha, o módulo `rewrite` está ligado mas ninguém o usa, e só a home responde.
`Require all granted` libera o acesso público à pasta.

---

## `docker/apache-tuning.conf`

Ajustes gerais, aplicados em cima do padrão do Apache.

```apache
ServerName localhost
```
Elimina o aviso `AH00558: Could not reliably determine the server's fully
qualified domain name` que polui os logs toda vez que o Apache sobe.

```apache
ServerTokens Prod
ServerSignature Off
```
Reduz o que o servidor conta sobre si mesmo. Em vez de anunciar
`Apache/2.4.68 (Debian)` nos cabeçalhos e nas páginas de erro, diz só `Apache`.
Não impede ataque nenhum sozinho, mas não há motivo para entregar a versão
exata de graça.

```apache
Timeout 300
KeepAlive On
KeepAliveTimeout 5
MaxKeepAliveRequests 100
```
`Timeout 300` dá até 5 minutos para uma requisição terminar (relatórios e
uploads grandes agradecem).
`KeepAlive` reaproveita a mesma conexão TCP para várias requisições seguidas,
evitando o custo de reconectar; os outros dois limitam por quanto tempo e para
quantas requisições.

Estes valores vieram do `apache2.conf` antigo do projeto. A diferença é que
antes o arquivo **inteiro** era substituído, e ele incluía um
`Require all granted` na raiz do sistema de arquivos (`<Directory />`) — bem
mais aberto que o padrão do Debian, que nega. Preservamos o que era intencional
e descartamos o resto.

---

## `docker/php.ini`

```ini
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 24M
max_execution_time = 120
max_input_time = 120
expose_php = Off
```

A imagem oficial do PHP não ativa nenhum `php.ini` por padrão — vale tudo que
está compilado como padrão. Este arquivo materializa limites explícitos.

`memory_limit` — teto de memória por requisição. 128M (o padrão) costuma apertar
em importações e relatórios.
`upload_max_filesize` — maior arquivo que pode ser enviado.
`post_max_size` — maior corpo de requisição no total. Precisa ser **maior** que
o `upload_max_filesize`, porque além do arquivo vão junto os outros campos do
formulário; por isso 24M contra 20M.
`max_execution_time` / `max_input_time` — teto de tempo para o script rodar e
para receber os dados de entrada.
`expose_php = Off` — remove o cabeçalho `X-Powered-By: PHP/8.2.x`, mesma lógica
do `ServerTokens`.

Curiosidade: o `entrypoint.sh` antigo tinha um comentário dizendo "Aumentar
limites de upload e timeout do PHP" — e nenhum código que fizesse isso. Este
arquivo é aquela intenção, agora de verdade.

---

## `.dockerignore`

Lista o que **não** é enviado ao Docker na hora de construir a imagem. Funciona
como um `.gitignore`.

Serve a dois propósitos: deixar o build mais rápido (menos arquivos para
transferir) e evitar que coisas indesejadas entrem na imagem.

```
.git
.gitignore
docker-compose.yml
docker-compose.prod.yml
render.yaml
README.md
mysql-init
```
Nada disso é usado pela aplicação rodando. O `.git` sozinho costuma ser o item
mais pesado do projeto.

```
src/.env
```
**A linha mais importante aqui.** Impede que o seu `.env` local — com senhas,
`APP_KEY` e `APP_DEBUG=true` — seja assado dentro da imagem de produção.

```
src/vendor
src/node_modules
```
São reinstalados dentro da imagem, na versão certa e sem dependências de
desenvolvimento. Mandar os seus só faria o build demorar mais para depois
sobrescrever tudo.

```
src/public/build
src/public/hot
src/public/storage
src/database/database.sqlite
```
Arquivos gerados: build do Vite, marcador do servidor de desenvolvimento, o link
simbólico do storage (que aponta para um caminho da sua máquina e não
funcionaria no container) e o SQLite de teste.

```
src/storage/logs/*
src/storage/framework/cache/data/*
src/storage/framework/sessions/*
src/storage/framework/views/*
src/storage/app/public/*
```
Repare no `/*` no final de cada linha: ignoramos o **conteúdo**, não a pasta.

Isso é consequência direta de um erro. A primeira versão ignorava as pastas
inteiras, e o build quebrou em `php artisan view:cache` com `View path not
found`, porque o Laravel não tinha onde escrever as views compiladas. Hoje há
proteção dos dois lados: estes globs, e o `mkdir -p` no `Dockerfile`.

```
src/.phpunit.result.cache
src/tests
```
Testes não rodam em produção.

---

## `render.yaml`

Descreve o serviço para o Render. Com ele, o deploy é reproduzível: em vez de
clicar em vinte campos no painel, o Render lê este arquivo.

```yaml
services:
  - type: web
```
`web` é o tipo que recebe tráfego da internet e ganha uma URL pública.

```yaml
    name: modulo-autenticacao
    runtime: docker
```
`runtime: docker` diz para construir a partir do `Dockerfile`, em vez de tentar
adivinhar a linguagem.

```yaml
    plan: free
    region: oregon
```
Plano gratuito, região Oregon. Vale saber o que o plano free implica: o serviço
**hiberna após cerca de 15 minutos sem acesso**, e a primeira requisição depois
disso leva de 30 a 60 segundos para responder.

```yaml
    dockerfilePath: ./Dockerfile
    dockerContext: .
```
Onde está a receita e qual pasta é o material do build.

Lembre que **não existe** uma opção de target aqui. É por isso que o stage
`prod` é o último do `Dockerfile`.

```yaml
    healthCheckPath: /up
```
A URL que o Render consulta para saber se a aplicação está viva. Se parar de
responder, ele reinicia o container.

`/up` já vinha de graça: o `bootstrap/app.php` do Laravel 12 registra essa rota
por padrão.

```yaml
    envVars:
      - key: APP_NAME
        value: modulo-autenticacao
      - key: APP_ENV
        value: production
      - key: APP_DEBUG
        value: "false"
```
`APP_ENV: production` ativa o modo produção do Laravel.
`APP_DEBUG: "false"` é **crítico para segurança**: com debug ligado, qualquer
erro exibe o código-fonte, o caminho dos arquivos e o conteúdo das variáveis de
ambiente — senhas inclusive — para quem estiver acessando.

As aspas em `"false"` existem porque o YAML converteria `false` sem aspas num
booleano, e queremos a string que o Laravel entende.

```yaml
      - key: APP_KEY
        sync: false
      - key: APP_URL
        sync: false
```
`sync: false` significa "o valor não está neste arquivo; preencha no painel".

É assim que segredos ficam fora do Git. O Render mostra esses campos em branco
para você preencher no primeiro deploy.

`APP_KEY` — gere com `php artisan key:generate --show` e cole **incluindo** o
prefixo `base64:`.
`APP_URL` — a URL `.onrender.com` do serviço, que você só conhece depois do
primeiro deploy.

```yaml
      - key: LOG_CHANNEL
        value: stderr
      - key: LOG_LEVEL
        value: info
```
Manda os logs para a saída de erro em vez de gravar em arquivo.

Essencial em container: arquivo dentro do container some a cada deploy e ninguém
consegue ler. Em `stderr`, os logs aparecem no painel do Render.

`info` em vez de `debug` evita encher o painel de ruído.

```yaml
      - key: SESSION_DRIVER
        value: database
      - key: CACHE_STORE
        value: database
      - key: QUEUE_CONNECTION
        value: database
```
Guarda sessões, cache e filas no banco, não em arquivo.

Mesma razão: o disco do container é descartável. Sessão em arquivo significa
usuário deslogado a cada deploy. (Essas migrations já existem no projeto —
`create_cache_table` e `create_jobs_table`.)

```yaml
      - key: DB_CONNECTION
        value: mysql
      - key: DB_HOST
        sync: false
      - key: DB_PORT
        sync: false
      - key: DB_DATABASE
        sync: false
      - key: DB_USERNAME
        sync: false
      - key: DB_PASSWORD
        sync: false
```
Dados do MySQL externo, preenchidos no painel.

**O Render não oferece MySQL gerenciado** — só Postgres e Key Value
(compatível com Redis). Por isso o banco precisa vir de fora: Aiven, Clever
Cloud, Railway ou PlanetScale, por exemplo.

```yaml
      # Preencher com /etc/ssl/certs/ca-certificates.crt se o provedor exigir TLS
      - key: MYSQL_ATTR_SSL_CA
        sync: false
```
Vários provedores de MySQL na nuvem exigem conexão criptografada.

O `config/database.php` do Laravel passa essa variável para o PDO envolvida num
`array_filter` — ou seja, **se ficar vazia, é simplesmente ignorada**. Por isso
pode ficar declarada sem valor sem causar problema: fica à disposição, e você
preenche só se o provedor exigir. O caminho indicado existe na imagem base
(verificado).

---

## `docker-compose.prod.yml`

Para rodar em VPS. A estrutura é parecida com a do compose de desenvolvimento,
com diferenças que importam.

```yaml
  php:
    build:
      context: .
      target: prod
    image: modulo-autenticacao:prod
```
Agora é `target: prod`: código copiado para dentro, dependências sem as de
desenvolvimento, opcache travado.
`image:` dá um nome fixo à imagem construída, facilitando inspeção e limpeza.

```yaml
    restart: unless-stopped
```
Reinicia o container sozinho se ele cair ou se a VPS reiniciar. Só não reinicia
se você mesmo tiver parado.

```yaml
    environment:
      PORT: 80
```
Na VPS ninguém injeta `PORT`, então definimos. O `sed` do entrypoint cuida do
resto.

```yaml
      APP_KEY: ${APP_KEY:?defina APP_KEY no .env ao lado deste arquivo}
      APP_URL: ${APP_URL:?defina APP_URL}
```
`${VAR:?mensagem}` é uma rede de proteção: se a variável não estiver definida, o
compose **se recusa a subir** e mostra a mensagem.

Melhor do que subir com `APP_KEY` vazia e descobrir pelo erro 500.

Os valores vêm de um arquivo `.env` na raiz do projeto, que o compose lê
automaticamente. Use o `.env.deploy.example` como modelo.

```yaml
      DB_HOST: db
```
`db` é o nome do serviço MySQL logo abaixo. Na rede do compose, o nome do
serviço funciona como endereço.

```yaml
    volumes:
      - app_storage:/var/www/html/storage/app/public
```
Preserva arquivos enviados por usuários entre deploys.

Sem isso, toda reconstrução do container apagaria os uploads. É uma vantagem
concreta da VPS sobre o plano free do Render, onde isso não é possível.

```yaml
    ports:
      - "127.0.0.1:8099:80"
```
Repare no `127.0.0.1:` na frente. Sem ele, a porta ficaria aberta para a
internet inteira.

Com ele, a aplicação só é alcançável de dentro da própria máquina — e quem fala
com o mundo é o proxy reverso. Isso também é o que torna seguro o
`trustProxies('*')` do Laravel.

```yaml
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:?defina DB_ROOT_PASSWORD}
```
Diferente do compose de desenvolvimento, aqui **não há senha escrita no
arquivo** — todas vêm do `.env`, que fica fora do Git.

```yaml
volumes:
  mysql_data:
  app_storage:
```
Os dois volumes nomeados. **São eles que guardam tudo que importa**: o banco e
os uploads. Faça backup deles.

### O que falta numa VPS

A imagem serve HTTP puro. O Render coloca HTTPS na frente de graça; numa VPS,
você precisa de um proxy reverso. O Caddy é o caminho mais curto, porque cuida
do certificado Let's Encrypt sozinho:

```
seu-dominio.com {
    reverse_proxy 127.0.0.1:8099
}
```

Também passa a ser sua responsabilidade: atualizar o sistema operacional,
configurar firewall e fazer backup dos volumes.

---

## `.env.deploy.example`

```
APP_KEY=
APP_URL=https://seu-dominio.com

DB_DATABASE=modulo_autenticacao
DB_USERNAME=modulo_autenticacao
DB_PASSWORD=
DB_ROOT_PASSWORD=
```

Modelo do `.env` que o `docker-compose.prod.yml` espera na raiz do projeto.
Copie, preencha e **nunca comite o resultado** — o `.gitignore` da raiz já cobre
isso.

Não confunda com `src/.env`, que é o arquivo da aplicação em desenvolvimento.
Este aqui só alimenta o compose de produção.

---

## Alterações no código Laravel

Duas mudanças fora do Docker foram necessárias para o deploy funcionar.

### `src/bootstrap/app.php` — confiar no proxy

```php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->trustProxies(at: '*');
})
```

Em produção o container nunca fala direto com o usuário. Quem recebe a conexão
é a borda do Render (ou o seu proxy na VPS), que cuida do HTTPS e repassa a
requisição em HTTP simples para dentro.

Sem esta linha, o Laravel olha a conexão que chegou, vê HTTP, e conclui que o
site é HTTP. Resultado: links e redirecionamentos gerados em `http://`, o que
causa redirect infinito e conteúdo bloqueado pelo navegador.

Com ela, o Laravel passa a confiar no cabeçalho `X-Forwarded-Proto` que o proxy
envia, e entende que o usuário está em HTTPS.

O `'*'` (confiar em qualquer proxy) é aceitável porque o container nunca fica
exposto: no Render só a borda o alcança, e no compose de produção ele está
preso em `127.0.0.1`.

### `src/.env.example` — apontar para o MySQL

Vinha com `DB_CONNECTION=sqlite` e todo o resto comentado. Como o entrypoint de
desenvolvimento faz `cp .env.example .env` num clone novo, isso criaria um
ambiente SQLite silenciosamente diferente do MySQL que o compose sobe ao lado.
Agora o modelo reflete o `docker-compose.yml`.

---

## Problemas comuns

**`localhost:8099` não responde**
Confira `docker compose ps`. Se o serviço `php` estiver reiniciando em loop, veja
`docker compose logs php`.

**Erro 500 na página inicial, mas `/up` responde 200**
Quase sempre é banco: as migrations não rodaram. Como `SESSION_DRIVER=database`,
a tabela `sessions` precisa existir.
```bash
docker compose exec php php artisan migrate
```

**Alterei o `.env` e nada mudou**
```bash
docker compose exec php php artisan config:clear
```

**Permissão negada em `storage/`**
```bash
docker compose exec php chown -R www-data:www-data storage bootstrap/cache
```

**O banco sumiu depois de um `docker compose down -v`**
A flag `-v` apaga os volumes, incluindo o `mysql_data`. Use `docker compose down`
sem `-v` para desligar preservando os dados.

**Mudei o `Dockerfile` e não surtiu efeito**
Reconstrua: `docker compose up -d --build`.

**O deploy no Render falhou logo no começo, com `ERRO: variavel de ambiente ... nao definida`**
É a guarda do entrypoint de produção funcionando. Preencha no painel a variável
que a mensagem citou.
