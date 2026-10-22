<?php

namespace App\OpenApi;

use OpenApi\Attributes as OA;

#[OA\Info(
    version: '1.0.0',
    title: 'Módulo de Autenticação',
    description: 'API de autenticação em Laravel 12.',
)]
#[OA\SecurityScheme(
    securityScheme: 'bearerAuth',
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
    description: 'Token de acesso enviado no header Authorization: Bearer <token>',
)]
final class OpenApiSpec
{
    #[OA\Get(
        path: '/up',
        summary: 'Health check da aplicação',
        tags: ['Infraestrutura'],
        security: [],
        responses: [
            new OA\Response(response: 200, description: 'Aplicação saudável'),
            new OA\Response(response: 500, description: 'Aplicação com falha'),
        ],
    )]
    public function health(): void
    {
    }
}
