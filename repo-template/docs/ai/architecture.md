# Architecture notes

> Source commit: `[UNVERIFIED]`  
> Last verified: `[UNVERIFIED]`  
> Confidence: `[UNVERIFIED]`

## Arquitetura real

Descreva a arquitetura observada no repositório, não uma arquitetura desejada. Diferencie fatos, inferências e dívidas.

- Tipo:
- Camadas:
- Padrão dominante:
- Padrões mistos:

## Dependências observadas

```text
[exemplo]
Web -> Application -> Domain
Web -> Infrastructure
Infrastructure -> Database
```

## Padrões encontrados

- Controllers/PageModels:
- Serviços:
- Repositórios:
- Validações:
- DTOs/ViewModels:
- Logs:
- Tratamento de erros:

## Regras de implementação

- Onde colocar nova regra de negócio:
- Onde colocar novo endpoint:
- Onde colocar nova tela/componente:
- Onde colocar query/repositório:
- Onde colocar validação:

## Débitos técnicos relevantes

| Débito | Impacto | Risco | Recomendação |
|---|---|---|---|
| [descrição] | [impacto] | [baixo/médio/alto] | [ação] |

## Decisões conhecidas

Registre decisões arquiteturais já tomadas, incluindo fonte e data de verificação quando disponível.

- ...

## Não fazer

- Não mover camadas sem plano.
- Não padronizar tudo em uma feature pequena.
- Não introduzir framework novo sem justificativa forte.
- Não quebrar contratos existentes sem plano de migração.
