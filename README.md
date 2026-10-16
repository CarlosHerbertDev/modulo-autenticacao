# modulo-autenticacao

inicar container com um composer up, botão direito no arquivo docker-compose.yml

Rodas os proximos comandos dentro do container 

1. entar no container docker exec -it modulo_autenticacao bash

2 entrar no container depois de montado e dar um composer install

3 liberar permissões com chmod -R 777 ./

4 gerar env através do env example com o comando cp .env.example .env

5 gerar chave com php artisan key:generate

6 gerar migrations para banco com php artisan migrate 

7 gerar link simbolico para acessar imagens php artisan storage:link

agora basta acessar o local host em localhost:8070

e acessar a doc das apis em localhost:8070/api/documentation