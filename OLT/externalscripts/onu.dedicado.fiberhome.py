#!/usr/bin/env python3
"""
onu.dedicado.fiberhome.py - Descobre ONUs dedicadas em OLTs Fiberhome via SNMP walk.

Filtra por regex sobre a descricao da ONU (OID 1.3.6.1.4.1.5875.800.3.10.1.1.7).
Retorna LLD JSON com metadados: desc, index (slot.port.onu), SN.

Uso: onu.dedicado.fiberhome.py <IP> <COMMUNITY> [PORT] [REGEX_FILTER]
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
FILTER_RE = sys.argv[4] if len(sys.argv) > 4 else r"^(dedicado-|[0-9])(?=.*[a-z]{4,})"

SNMP_TARGET = "%s:%s" % (OLT_IP, PORT) if PORT != "161" else OLT_IP
OPTS = ["-v2c", "-c", COMMUNITY, "-t", "20", "-r", "1", SNMP_TARGET]

# Fiberhome ONU table OIDs (GEPON-OLT-COMMON-MIB / proprietary)
OID_DESC = "1.3.6.1.4.1.5875.800.3.10.1.1.7"   # onuDesc / descricao da ONU
OID_SN   = "1.3.6.1.4.1.5875.800.3.10.1.1.10"  # onuSn / serial number

try:
    filter_compiled = re.compile(FILTER_RE, re.IGNORECASE)
except re.error:
    filter_compiled = re.compile(r"^dedicado-", re.IGNORECASE)


def snmpwalk(oid):
    """Executa snmpbulkwalk e retorna lista de (index_suffix, value_raw)."""
    try:
        out = subprocess.check_output(
            ["snmpbulkwalk"] + OPTS + [oid],
            stderr=subprocess.DEVNULL, timeout=30
        ).decode(errors="ignore")
    except Exception:
        return []
    result = []
    oid_suffix = oid.split("1.3.6.1.4.1.5875.")[-1]
    for line in out.splitlines():
        # Formato: SNMPv2-SMI::enterprises.5875.800.3.10.1.1.7.S.P.O = STRING: "desc"
        m = re.search(r"5875\." + re.escape(oid_suffix) + r"\.(\S+)\s*=\s*(.+)", line)
        if not m:
            m = re.search(r"\." + re.escape(oid_suffix) + r"\.(\S+)\s*=\s*(.+)", line)
        if m:
            result.append((m.group(1), m.group(2).strip()))
    return result


def parse_string(raw):
    m = re.search(r'(?:STRING|OCTET STRING):\s*"([^"]*)"', raw)
    if m:
        return m.group(1)
    m = re.search(r'(?:STRING|OCTET STRING):\s*(.+)', raw)
    if m:
        return m.group(1).strip().strip('"')
    return raw.strip()


def parse_sn(raw):
    # Fiberhome SN pode vir como Hex-STRING ou STRING
    m = re.search(r'Hex-STRING:\s*([\dA-Fa-f\s]+)', raw)
    if m:
        bytes_hex = m.group(1).strip().split()
        try:
            return "".join(chr(int(b, 16)) if 32 <= int(b, 16) < 127 else "."
                           for b in bytes_hex)
        except Exception:
            return m.group(1).strip().replace(" ", "")
    return parse_string(raw)


# Coletar descricoes
desc_map = {}
for idx, raw in snmpwalk(OID_DESC):
    desc_map[idx] = parse_string(raw)

# Filtrar dedicados
dedicated = [(idx, desc) for idx, desc in desc_map.items()
             if filter_compiled.match(desc)]

if not dedicated:
    print(json.dumps({"data": []}))
    sys.exit(0)

# Coletar SNs
sn_raw = {idx: raw for idx, raw in snmpwalk(OID_SN)}

lld = []
for idx, desc in sorted(dedicated, key=lambda x: x[0]):
    sn = parse_sn(sn_raw.get(idx, "")) if idx in sn_raw else ""
    lld.append({
        "{#NETSTREAM.ONU_DESC}":  desc,
        "{#NETSTREAM.ONU_INDEX}": idx,
        "{#SNMPINDEX}":           idx,
        "{#NETSTREAM.ONU_SN}":   sn,
    })

print(json.dumps({"data": lld}))
