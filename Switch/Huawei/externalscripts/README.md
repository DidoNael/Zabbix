# Scripts Externos para Zabbix (`externalscripts`)

Esta pasta contém os scripts externos necessários para o funcionamento completo das regras de descoberta e monitoramento dos templates **Switch Huawei** (versões 4.4 e 6.0).

---

## 1. `get_asn_owner_v2.sh`

Script responsável por consultar automaticamente o nome da organização/provedor proprietário de um **ASN (Autonomous System Number)** descoberto nas sessões BGP (IPv4 e IPv6).

### Características Principais
- **Cache Local em Disco (`/tmp/zabbix_asn_cache`):** Armazena o resultado por **30 dias**, respondendo em **menos de 3 milissegundos** e reduzindo a carga do Zabbix Server praticamente a zero.
- **Proteção contra travamento (`timeout 4s`):** Se os servidores WHOIS externos estiverem lentos ou indisponíveis, a consulta é abortada rapidamente para não prender processos *poller* do Zabbix.
- **Arquitetura de 6 Camadas de Fallback:**
  1. **Cache Local:** Retorno instantâneo do disco.
  2. **RADB WHOIS:** `whois.radb.net` (Porta 43).
  3. **WHOIS Padrão:** Registro regional (LACNIC/ARIN/RIPE).
  4. **LACNIC Web:** Consulta via HTTPS no LACNIC.
  5. **RIPE Stat API Global:** API REST cobrindo ASNs de todos os continentes.
  6. **BGPView API Global:** API REST secundária.
  7. **Fallback de Resiliência:** Caso todas as fontes de rede falhem, serve o cache antigo ou retorna `AS<ASN>`.

---

## 2. Instalação no Servidor Zabbix

1. Copie o arquivo `get_asn_owner_v2.sh` para o diretório oficial de scripts externos do seu Zabbix Server:
   ```bash
   cp get_asn_owner_v2.sh /usr/lib/zabbix/externalscripts/get_asn_owner_v2.sh
   ```

2. Defina permissão de execução e propriedade correta:
   ```bash
   chmod +x /usr/lib/zabbix/externalscripts/get_asn_owner_v2.sh
   chown root:root /usr/lib/zabbix/externalscripts/get_asn_owner_v2.sh
   ```

---

## 3. Teste de Funcionamento

Execute o script passando um número de AS (exemplo: `36351`):

```bash
time /usr/lib/zabbix/externalscripts/get_asn_owner_v2.sh 36351
```

- **1ª Execução (Sem Cache):** Consulta na rede e gera o cache (tempo médio: `0.8s - 1.5s`).
- **2ª Execução (Com Cache):** Lê direto do disco (tempo médio: `< 0.005s`).

Para inspecionar o cache salvo no servidor:
```bash
ls -lh /tmp/zabbix_asn_cache/
cat /tmp/zabbix_asn_cache/AS36351.txt
```
