# Zabbix Templates

Repositório centralizado de templates customizados para o Zabbix, otimizados para monitoramento de ativos de rede e infraestrutura de provedores.

---

## Templates Disponíveis

### 1. ZTE GPON OLT (`ZTE.xml`)
Template otimizado e corrigido para compatibilidade com o **Zabbix 4.4+**.

#### Principais Características e Correções:
* **Alinhamento de Índices SNMP (Join LLD via JavaScript):** Resolve o desalinhamento entre o índice padrão de interfaces (code 26) e o índice de ONUs autorizadas proprietário ZTE (code 28). O script de pré-processamento JavaScript unifica os registros automaticamente, permitindo o correto funcionamento dos filtros.
* **Filtros Nativos Corrigidos:** Configurado com os tipos de dados constantes originais compatíveis com o validador do Zabbix 4.4 (`AND` para avaliação de filtros e `NOT_MATCHES_REGEX` para operadores), eliminando erros de importação.
* **Tratamento de Prefixos GPON:** Suporta nomes de interface iniciados por `gpon_`, `gpon-olt_` ou `gpon-`.
* **Alarmes Dinâmicos de Queda (Massiva):**
  * Criação do item calculado `gpon.onu.online_antes` para registrar o status histórico de ONUs online.
  * Trigger de queda massiva baseada na macro customizável `{$GPON_DROP_MIN}` (padrão: `5`).
  * Disparo inteligente: o alerta só é ativado em portas GPON ativas com **mais de 2 clientes autorizados**, evitando alarmes falsos em portas sob teste ou sem clientes.
* **Alarme de Porta GPON Cheia:** Alerta ativo quando uma porta GPON operacionalmente ativa (`UP`) excede 127 clientes autorizados.
* **Mapeamento de Placas Físicas (Value Mapping):** Mapeamento do tipo de placa física baseado em OID SNMP (ex: `135 = GTOH`, `119 = GTGH`, `43 = GU1A`, `48 = GU1F`, `1 = Slot vazio/desconhecido`), com remoção de triggers redundantes de temperatura de slots inativos.

---

## Como Utilizar o Template ZTE

1. **Importação:**
   * Acesse `Configuration` > `Templates` > `Import` no seu painel do Zabbix.
   * Escolha o arquivo `ZTE.xml` deste repositório e clique em **Import**.
2. **Macros de Host / Template:**
   * Certifique-se de configurar a macro `{$SNMP_COMMUNITY}` com a comunidade SNMP correta.
   * Ajuste a macro `{$GPON_DROP_MIN}` (padrão `5`) caso queira alterar a sensibilidade do alarme de queda massiva.
3. **Associação:**
   * Associe o template aos seus hosts ZTE GPON OLT (modelos C300, C320, C350, etc.).

---

## Versionamento e Tags

Utilizamos tags do Git para marcar versões estáveis dos templates. Isso facilita o rollback e a distribuição controlada dos arquivos.

* Para visualizar as tags disponíveis:
  ```bash
  git tag
  ```
* Para criar uma nova tag de versão (ex: `v1.1.0`):
  ```bash
  git tag -a v1.1.0 -m "Adicionado template de Switch Huawei"
  git push origin v1.1.0
  ```

---

## Como Adicionar Novos Templates

1. Salve o arquivo XML/YAML do novo template na raiz ou em uma pasta organizada (ex: `huawei/`, `datacom/`).
2. Adicione e faça o commit do arquivo:
   ```bash
   git add .
   git commit -m "Add: Template para Switch Huawei Metro"
   ```
3. Envie para o branch principal:
   ```bash
   git push origin main
   ```
4. Crie uma nova tag para marcar a entrega estável.
