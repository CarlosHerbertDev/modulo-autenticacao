## Regras gerais

- Sempre responda em português
- Não adicione comentários no código 
- Não faça atividades além das solicitadas 
- Prefira respostas objetivas, sem preâmbul

## Regras de Código & Padrões Laravel 12

### 1. Tipagem e Declarações Estritas
- Sempre adicione `declare(strict_types=1);` no topo de todos os novos arquivos PHP.
- Utilize tipagem estrita nativa nos argumentos e retornos de métodos.
- Evite PHPDoc redundante (ex: não adicione `@param string $name` se o argumento já possuir o tipo `string $name`).

### 2. Arquitetura e Configurações (Bootstrap Slim)
- Toda e qualquer configuração de rotas, middlewares ou exceções globais deve ser feita exclusivamente no arquivo `bootstrap/app.php`. Os arquivos `Http/Kernel.php` e `Console/Kernel.php` foram removidos no Laravel 12.
- Agrupe middlewares no `bootstrap/app.php` utilizando `$middleware->alias()` se necessário.

### 3. Convenções do Eloquent ORM
- **UUIDv7 por padrão:** Ao utilizar a trait `HasUuids`, lembre-se de que o Laravel 12 gera UUIDv7 de forma nativa e automática.
- **Attributes para Scopes:** Prefira utilizar os novos atributos PHP (`#[Scope]`) no topo dos métodos de escopo do model em vez do antigo prefixo de texto `scopeNome`.
- **Valores Condicionais:** Utilize a paginação por cursor (`cursorPaginate`) e o encadeamento de métodos do Laravel 12 como `.toResource()` ou `.toResourceCollection()` diretamente em queries Eloquent.
- **Método Except:** Use o método `->except()` nativo em coleções de models ou resultados do Eloquent se precisar omitir colunas dinamicamente.

### 4. Validação e Segurança
- Use sempre **Form Requests** dedicados (`php artisan make:request`) para validações em rotas controladas por Controllers.
- Utilize classes de regras invocáveis (`invokable`) para lógicas de validação customizadas.
- O armazenamento privado padrão mudou no Laravel 12: arquivos locais não públicos devem ir para `storage/app/private`.

### 5. Tratamento de Respostas e APIs
- Padronize retornos de API utilizando **Eloquent API Resources**.
- Mantenha respostas JSON limpas utilizando o padrão PascalCase ou camelCase nas 