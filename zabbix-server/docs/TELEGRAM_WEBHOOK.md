# Telegram Webhook — NETSTREAM

Media type configurado no Zabbix: **Telegram Reply+** (tipo Script/Webhook).

Documentação do sistema de notificação Telegram integrado ao Zabbix, incluindo todas as funcionalidades implementadas, parâmetros de configuração e padrões operacionais.

---

## Visão geral das funcionalidades

| Funcionalidade | Descrição |
|---|---|
| **Notificação de problema** | Envia mensagem formatada com severidade, host e trigger |
| **Reply na recuperação** | Mensagem de RESOLVIDO chega como resposta à mensagem original |
| **Edição na recuperação** | Alternativa ao reply: edita a mensagem original (modo `edit`) |
| **Botão Ver no Zabbix** | Link direto para o evento no Zabbix (inline keyboard) |
| **Botão Grafana** | Link para dashboard Grafana (quando `GrafanaURL` configurado) |
| **Pin de críticos** | Pina automaticamente alertas com severidade ≥ limiar configurado |
| **Unpin na recuperação** | Despina automaticamente quando incidente é resolvido |
| **Board de incidentes** | Mensagem pinada atualizada em tempo real com todos os incidentes abertos |
| **Múltiplos chat_ids** | Envia para vários grupos/canais separados por vírgula |
| **Horário de silêncio** | Suprime ou silencia notificações de baixa prioridade em horário configurado |
| **Persistência de tags** | Salva `tg_msg_id` e `tg_chat_id` no evento Zabbix via `event.acknowledge` |

---

## Parâmetros do media type

Configurar em **Administração → Tipos de mídia → Telegram Reply+ → Parâmetros**.

### Obrigatórios

| Parâmetro | Macro Zabbix | Descrição |
|---|---|---|
| `Token` | — | Token do bot Telegram |
| `To` | `{ALERT.SENDTO}` | chat_id(s) destino, separados por vírgula |
| `Subject` | `{ALERT.SUBJECT}` | Assunto da notificação |
| `Message` | `{ALERT.MESSAGE}` | Corpo da notificação |
| `EventID` | `{EVENT.ID}` | ID do evento Zabbix |
| `EventValue` | `{EVENT.VALUE}` | 1=problema, 0=recuperação |
| `ZabbixURL` | `{$ZABBIX.URL}` ou URL fixa | URL base do Zabbix (ex: `https://zabbix.exemplo.com.br`) |
| `ZabbixToken` | — | Token de API Zabbix (usuário de serviço) |

### Opcionais

| Parâmetro | Valor padrão | Descrição |
|---|---|---|
| `TriggerID` | `{TRIGGER.ID}` | Usado para montar link do Zabbix |
| `TriggerPriority` | `{TRIGGER.NSEVERITY}` | Severidade numérica (0–5). **Usar `NSEVERITY`, não `PRIORITY`** |
| `ParseMode` | `html` | Modo de formatação: `html`, `markdown`, `markdownv2` |
| `MessageThreadID` | — | ID do tópico (para grupos com tópicos habilitados) |
| `HTTPProxy` | — | Proxy HTTP, se necessário |
| `RecoveryMode` | `reply` | `reply` = resposta à msg original; `edit` = edita a mensagem |
| `PinCritical` | `false` | `true` = pina alertas com severidade ≥ `PinMinPriority` |
| `PinMinPriority` | `4` | Severidade mínima para pinar (4=High, 5=Disaster) |
| `TimezoneOffset` | `-3` | Offset UTC para horários no board (BRT = -3) |
| `SilentHoursStart` | `-1` | Hora início do período silencioso (0–23; -1 = desativado) |
| `SilentHoursEnd` | `-1` | Hora fim do período silencioso |
| `SilentMaxPriority` | `-1` | Prioridade máxima afetada pelo silêncio (-1 = desativado) |
| `GrafanaURL` | — | URL do dashboard Grafana (exibe botão extra na notificação) |

---

## Board de incidentes ativos

### O que é

Mensagem única e pinada no grupo Telegram que lista todos os incidentes abertos. Atualizada automaticamente a cada alerta de problema ou recuperação.

### Formato

```
📌 Relatório de Incidentes Ativos
Atualizado: 03/10 09:06 • 2 abertos

[Host]: BGP-SEMLIMITE_NE20
[Trigger]: Switch Huawei NQA [CLI_DIGITALNET_FORTALEZA]: Link inacessível (100% perda)
[⏰]: 03/10 09:05
[Duração]: 1min

[Host]: ASR 1002X - IGUATU - CE
[Trigger]: BGP peer - IP 10.79.79.21: ASN (263445) - DOWN
[⏰]: 03/10 08:19
[Duração]: 47min
```

### Como funciona

1. No primeiro alerta, o webhook envia a mensagem de board e pina no chat.
2. O `message_id` resultante é salvo no macro global `{$TG_BOARD_MSG_ID}`.
3. Em todos os alertas subsequentes (problema ou recuperação), o webhook busca os incidentes abertos via `problem.get` e edita a mensagem existente.
4. Exibe no máximo 12 incidentes; se houver mais, indica `+N mais`.
5. Ordenados por severidade (mais grave primeiro).

### Macro global necessária

| Macro | Valor inicial | Descrição |
|---|---|---|
| `{$TG_BOARD_MSG_ID}` | *(vazio)* | ID da mensagem do board. Preenchido automaticamente na primeira execução. |

> **Atenção:** se a mensagem do board ficar enterrada no histórico do chat (ex: após migração de grupo para supergrupo), zerar o macro para forçar criação de nova mensagem:
> ```python
> # Via API Zabbix
> usermacro.updateglobal({ globalmacroid: 'X', value: '' })
> ```

---

## Persistência de mensagens entre problema e recuperação

O Zabbix 7.2 não suporta `tags` em `event.acknowledge`. O webhook usa um workaround:

1. **Ao criar o alerta**: salva `tg_msg_id` e `tg_chat_id` como texto numa mensagem de acknowledge:
   ```
   tg_webhook: tg_msg_id=12345 tg_chat_id=-1003638264145
   ```
2. **Na recuperação**: lê os acknowledges do evento via `event.get` com `selectAcknowledges`, localiza a entrada `tg_webhook:` e extrai os valores.

> Esta abordagem é compatível com Zabbix 7.2. O suporte nativo a tags em `event.acknowledge` foi introduzido no Zabbix 7.4.

---

## Supergrupo Telegram — migração de chat_id

Quando um grupo Telegram é promovido a supergrupo, o `chat_id` muda. Sintoma no log:

```
Telegram sendMessage: group chat was upgraded to a supergroup chat
```

A resposta da API Telegram inclui `migrate_to_chat_id` com o novo ID. Atualizar o `sendto` do usuário de mídia no Zabbix com o novo ID (prefixo `-100`).

---

## Horário de silêncio

| Cenário | Comportamento |
|---|---|
| `priority <= 1` (Not classified/Info) dentro do horário | Mensagem **suprimida** completamente (não enviada) |
| `priority` entre 2 e `SilentMaxPriority` dentro do horário | Mensagem enviada com `disable_notification: true` (sem som/vibração) |
| Fora do horário de silêncio | Comportamento normal |

O horário suporta virada de meia-noite (ex: `SilentHoursStart=23`, `SilentHoursEnd=7`).

---

## Trigger BGP — padrão anti-flap

### Problema original

Expressões `last(#1)<>6 and last(#2)=6` e `diff()=1` disparavam a cada transição de estado do peer BGP (idle → connect → active → established → idle), gerando alarmes repetidos em casos de flap.

### Solução padrão (a partir de v2.14.1)

**Expressão** (6.0):
```
min(/TEMPLATE/netstream.BgpPeerState.[{#IP}.{#ASN}],#3)<>6
and last(/TEMPLATE/netstream.BgpPeerAdminStatus[{#IP}.{#ASN}])=2
and length(last(/TEMPLATE/get_asn_owner_netstream.sh[{#ASN},{#IP}]))>0
```

**Recovery expression**:
```
last(/TEMPLATE/netstream.BgpPeerState.[{#IP}.{#ASN}])=6
```

**Expressão equivalente 4.4**:
```
{TEMPLATE:netstream.BgpPeerState.[{#IP}.{#ASN}].min(#3)}<>6
and {TEMPLATE:netstream.BgpPeerAdminStatus[{#IP}.{#ASN}].last()}=2
and {TEMPLATE:get_asn_owner_netstream.sh[{#ASN},{#IP}].strlen()}>0
```

**Regras**:
- `min(#3)<>6` — peer precisa estar não-estabelecido em 3 amostras consecutivas (≈3 min com delay=1m)
- `adminStatus=2` — só alarma se peer estiver administrativamente habilitado
- Recovery explícita — recupera imediatamente quando peer volta ao estado established (6)
- Aplica a IPv4 (`netstream.bgppeerv4`) e IPv6 (`netstream.bgppeerv6`)

### Estados BGP (RFC 4271)

| Valor | Estado |
|---|---|
| 1 | Idle |
| 2 | Connect |
| 3 | Active |
| 4 | OpenSent |
| 5 | OpenConfirm |
| **6** | **Established** ← único estado saudável |

---

## Checklist de configuração inicial

- [ ] Criar bot Telegram via @BotFather e obter token
- [ ] Adicionar bot ao grupo e obter `chat_id` (via `getUpdates` ou mensagem de erro na primeira tentativa)
- [ ] Criar usuário de serviço no Zabbix com permissão de API (`Super Admin` ou perfil customizado com `event.acknowledge`)
- [ ] Configurar media type **Telegram Reply+** com todos os parâmetros obrigatórios
- [ ] Criar macro global `{$TG_BOARD_MSG_ID}` com valor vazio
- [ ] Criar macro global `{$ZABBIX.URL}` com URL base do Zabbix
- [ ] Configurar action de notificação filtrando por tag `notificar=telegram`
- [ ] Testar com um problema real ou forçar via "Executar agora" em um trigger de teste

---

## Referências

- Webhook JS: salvo diretamente no Zabbix (Media type → Script)
- Macro global board: `{$TG_BOARD_MSG_ID}` (globalmacroid=4 em produção)
- Chat de produção: `-1003638264145` (DidoNael - NETSTREAM)
- Log do webhook: `/var/log/zabbix/zabbix_server.log` — filtrar por `[TG+]`
