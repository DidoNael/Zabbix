#!/usr/bin/env python3
"""
nmap_security_discovery.py — Zabbix LLD External Script
Recebe um alvo (IP único, range ou CIDR) e retorna portas abertas suspeitas.

Estratégia: divide o alvo em blocos /28 e escaneia em paralelo,
evitando timeout por bloco /24 inteiro.
"""
import subprocess
import json
import sys
import ipaddress
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed

# ─── Banco de portas suspeitas ────────────────────────────────────────────────
PORT_DATA = {
    "21":    {"cat": "GERÊNCIA E ACESSO",          "prob": "FTP",                  "fator": "Senha em texto plano."},
    "22":    {"cat": "GERÊNCIA E ACESSO",          "prob": "SSH",                  "fator": "Alvo de Brute Force."},
    "23":    {"cat": "GERÊNCIA E ACESSO",          "prob": "Telnet",               "fator": "CRÍTICO: Sem criptografia."},
    "80":    {"cat": "GERÊNCIA E ACESSO",          "prob": "HTTP Admin",           "fator": "Interface Web de gerência exposta."},
    "443":   {"cat": "GERÊNCIA E ACESSO",          "prob": "HTTPS Admin",          "fator": "Interface Web SSL exposta."},
    "179":   {"cat": "INFRAESTRUTURA",             "prob": "BGP",                  "fator": "Risco de Sequestro de Prefixo (Hijacking)."},
    "8291":  {"cat": "GERÊNCIA E ACESSO",          "prob": "Winbox",               "fator": "Gerência MikroTik Exposta."},
    "10001": {"cat": "INFRAESTRUTURA",             "prob": "Ubiquiti Discovery",   "fator": "Vaza dados de topologia Ubiquiti."},
    "19":    {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "CharGen DDoS",         "fator": "Vetor de amplificação UDP."},
    "53":    {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "DNS Recursivo",        "fator": "Uso em ataques de reflexão DNS."},
    "111":   {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "RPCBind / Portmap",    "fator": "Vulnerável a enumeração e DDoS."},
    "123":   {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "NTP Monlist",          "fator": "Vetor de amplificação de DDoS."},
    "161":   {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "SNMP",                 "fator": "Vaza dados da rede e serve para DDoS."},
    "1900":  {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "SSDP/UPnP",           "fator": "Amplificação via dispositivos IoT."},
    "11211": {"cat": "DDOS E RPC (AMPLIFICAÇÃO)",  "prob": "Memcached",            "fator": "RISCO MÁXIMO: Amplificação 50.000x."},
    "1433":  {"cat": "BANCOS DE DADOS",            "prob": "MS-SQL",               "fator": "Banco Microsoft exposto."},
    "3306":  {"cat": "BANCOS DE DADOS",            "prob": "MySQL",                "fator": "Banco MySQL exposto."},
    "33060": {"cat": "BANCOS DE DADOS",            "prob": "MySQL X",              "fator": "Interface Shell do MySQL exposta."},
    "5432":  {"cat": "BANCOS DE DADOS",            "prob": "PostgreSQL",           "fator": "Banco PostgreSQL exposto."},
    "6379":  {"cat": "BANCOS DE DADOS",            "prob": "Redis",                "fator": "Acesso total se estiver sem senha."},
    "27017": {"cat": "BANCOS DE DADOS",            "prob": "MongoDB",              "fator": "Frequente alvo de Ransomware."},
    "445":   {"cat": "MALWARE E EXPLOITS",         "prob": "SMB/WannaCry",         "fator": "Risco de Ransomware EternalBlue."},
    "3333":  {"cat": "MALWARE E EXPLOITS",         "prob": "Minerador / Suspeito", "fator": "Possível Cryptojacking (Monero)."},
    "4444":  {"cat": "MALWARE E EXPLOITS",         "prob": "Metasploit",           "fator": "Porta padrão de Invasão (Shell)."},
    "5555":  {"cat": "MALWARE E EXPLOITS",         "prob": "Android ADB",          "fator": "Acesso direto a aparelhos Android."},
    "2375":  {"cat": "MALWARE E EXPLOITS",         "prob": "Docker API",           "fator": "Permite controle total do servidor."},
    "554":   {"cat": "VOIP E CFTV",                "prob": "RTSP (Vídeo)",         "fator": "Streaming de câmeras exposto."},
    "5060":  {"cat": "VOIP E CFTV",                "prob": "SIP Inseguro",         "fator": "Fraude telefônica e ataques DoS."},
    "8000":  {"cat": "VOIP E CFTV",                "prob": "Hikvision",            "fator": "Gerência de câmeras exposta."},
    "37777": {"cat": "VOIP E CFTV",                "prob": "Dahua DVR",            "fator": "Porta de DVRs alvo de botnets."},
}

ALL_PORTS = ",".join(PORT_DATA.keys())

# ─── Fracionamento do alvo ────────────────────────────────────────────────────

BLOCK_PREFIX = 28   # /28 = 16 IPs por bloco
MAX_WORKERS  = 12   # blocos paralelos simultâneos
BLOCK_TIMEOUT = 45  # segundos por bloco


def split_target(target: str, prefix: int = BLOCK_PREFIX):
    """
    Retorna lista de strings para o nmap:
    - IP único ou hostname → [target]
    - CIDR /28 ou menor    → [target]
    - CIDR maior que /28   → lista de sub-blocos /28
    """
    try:
        net = ipaddress.ip_network(target, strict=False)
    except ValueError:
        return [target]   # hostname ou range não-CIDR

    if net.prefixlen >= prefix:
        return [str(net)]

    return [str(sub) for sub in net.subnets(new_prefix=prefix)]


# ─── Scan de um bloco ─────────────────────────────────────────────────────────

def scan_block(block: str) -> list:
    cmd = [
        "nmap", "-p", ALL_PORTS,
        "-Pn", "-n",          # sem ping, sem DNS
        "-T4",
        "--open",
        "--min-rate", "2000",
        "--max-retries", "1",
        "-oX", "-",
        block,
    ]

    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=BLOCK_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return []   # bloco ignorado silenciosamente; outros blocos continuam

    results = []
    try:
        root = ET.fromstring(proc.stdout)
    except ET.ParseError:
        return []

    for host in root.findall("host"):
        addr_elem = host.find("address[@addrtype='ipv4']")
        if addr_elem is None:
            continue
        ip_addr = addr_elem.get("addr")

        ports = host.find("ports")
        if ports is None:
            continue

        for port in ports.findall("port"):
            p_id    = port.get("portid")
            p_proto = port.get("protocol", "tcp").upper()
            state   = port.find("state")

            if state is not None and state.get("state") == "open" and p_id in PORT_DATA:
                info = PORT_DATA[p_id]
                results.append({
                    "{#IP}":        ip_addr,
                    "{#PORTA}":     p_id,
                    "{#PROTOCOLO}": p_proto,
                    "{#CATEGORIA}": info["cat"],
                    "{#PROBLEMA}":  info["prob"],
                    "{#FATOR}":     info["fator"],
                    "ip":           ip_addr,
                    "porta":        p_id,
                    "fator":        info["fator"],
                })

    return results


# ─── Orquestrador ─────────────────────────────────────────────────────────────

def run_scan(target: str) -> list:
    blocks = split_target(target)

    if len(blocks) == 1:
        return scan_block(blocks[0])

    all_results = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(scan_block, b): b for b in blocks}
        for fut in as_completed(futures):
            try:
                all_results.extend(fut.result())
            except Exception:
                pass   # bloco falhou; continua com os demais

    return all_results


# ─── Entrada ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Nenhum alvo especificado"}))
        sys.exit(1)

    saida = run_scan(sys.argv[1])
    print(json.dumps(saida, indent=4, ensure_ascii=False))
