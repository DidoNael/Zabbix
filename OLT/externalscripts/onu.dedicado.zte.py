#!/usr/bin/env python3
"""
onu.dedicado.zte.py - Descobre todas as ONUs em OLTs ZTE via SNMP walk.

Retorna LLD JSON com metadados de todas as ONUs. O filtro por descricao
e aplicado pelo Zabbix via {$ONU_DEDICADO_FILTER.NETSTREAM} no DR.

Uso: onu.dedicado.zte.py <IP> <COMMUNITY> [PORT]
"""
import sys
import re
import json
import subprocess

if len(sys.argv) < 3:
    print(json.dumps({"data": []}))
    sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
PORT      = sys.argv[3] if len(sys.argv) > 3 else "161"

SNMP_TARGET = "%s:%s" % (OLT_IP, PORT) if PORT != "161" else OLT_IP
OPTS = ["-v2c", "-c", COMMUNITY, "-t", "20", "-r", "1", SNMP_TARGET]

OID_ONTDESC = "1.3.6.1.4.1.3902.1012.3.28.1.1.2"  # descricao da ONU
OID_MODEL   = "1.3.6.1.4.1.3902.1012.3.28.1.1.1"  # modelo/tipo
OID_SN_HEX  = "1.3.6.1.4.1.3902.1012.3.28.1.1.5"  # SN em hex (4 bytes ASCII + 4 bytes serial)


def snmpwalk(oid):
    """Executa snmpbulkwalk e retorna lista de (index, value_raw)."""
    try:
        out = subprocess.check_output(
            ["snmpbulkwalk"] + OPTS + [oid],
            stderr=subprocess.DEVNULL, timeout=30
        ).decode(errors="ignore")
    except Exception:
        return []
    result = []
    for line in out.splitlines():
        # ex: SNMPv2-SMI::enterprises.3902.1012.3.28.1.1.2.268700416.6 = STRING: "dedicado-..."
        m = re.match(r".*\." + re.escape(oid.split("1.3.6.1.4.1.3902.")[-1]) +
                     r"\.(\d+\.\d+)\s*=\s*(.+)", line)
        if not m:
            # fallback: pegar tudo apos o ultimo OID conhecido
            m2 = re.search(r"3902\.\d+.*?\.(\d+\.\d+)\s+=\s+(.+)", line)
            if m2:
                result.append((m2.group(1), m2.group(2).strip()))
        else:
            result.append((m.group(1), m.group(2).strip()))
    return result


def parse_string(raw):
    """Extrai string do valor SNMP: STRING: \"texto\" -> texto"""
    m = re.search(r'(?:STRING|OCTET STRING):\s*"([^"]*)"', raw)
    if m:
        return m.group(1)
    m = re.search(r'(?:STRING|OCTET STRING):\s*(.+)', raw)
    if m:
        return m.group(1).strip().strip('"')
    return raw.strip()


def parse_hexstr_to_sn(raw):
    """Converte Hex-STRING: XX XX XX XX XX XX XX XX para formato SN ZTE.
    Primeiros 4 bytes = ASCII do vendor, proximos 4 = hex do serial.
    Ex: 5A 54 45 47 CE C9 AA 9A -> ZTEGCEC9AA9A
    """
    m = re.search(r'Hex-STRING:\s*([\dA-Fa-f\s]+)', raw)
    if not m:
        # pode ser string normal
        return parse_string(raw)
    bytes_hex = m.group(1).strip().split()
    if len(bytes_hex) < 4:
        return ""
    try:
        vendor = "".join(chr(int(b, 16)) for b in bytes_hex[:4] if 32 <= int(b, 16) < 127)
        serial = "".join(b.upper() for b in bytes_hex[4:])
        return vendor + serial
    except Exception:
        return m.group(1).strip().replace(" ", "")


# Coletar descricoes
desc_map = {}   # index -> desc
for idx, raw in snmpwalk(OID_ONTDESC):
    desc = parse_string(raw)
    desc_map[idx] = desc

if not desc_map:
    print(json.dumps({"data": []}))
    sys.exit(0)

# Coletar modelo e SN para todas as ONUs
model_map = {}
for idx, raw in snmpwalk(OID_MODEL):
    model_map[idx] = parse_string(raw)

sn_map = {}
for idx, raw in snmpwalk(OID_SN_HEX):
    sn_map[idx] = parse_hexstr_to_sn(raw)

# Montar LLD (filtro aplicado pelo Zabbix via {$ONU_DEDICADO_FILTER.NETSTREAM})
lld = []
for idx, desc in sorted(desc_map.items(), key=lambda x: x[0]):
    lld.append({
        "{#NETSTREAM.ONU_DESC}":  desc,
        "{#NETSTREAM.ONU_INDEX}": idx,
        "{#SNMPINDEX}":           idx,
        "{#NETSTREAM.ONU_SN}":   sn_map.get(idx, ""),
        "{#NETSTREAM.ONU_MODEL}": model_map.get(idx, ""),
    })

print(json.dumps({"data": lld}))
