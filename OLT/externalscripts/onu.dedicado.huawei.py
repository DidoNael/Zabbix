#!/usr/bin/env python3
"""
onu.dedicado.huawei.py - Descobre todas as ONUs em OLTs Huawei via SNMP walk.

Retorna LLD JSON com metadados de todas as ONUs. O filtro por descricao
e aplicado pelo Zabbix via {$ONU_DEDICADO_FILTER.NETSTREAM} no DR.

Uso: onu.dedicado.huawei.py <IP> <COMMUNITY> [PORT]
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

# Huawei GPON ONU OIDs (HUAWEI-XPON-MIB)
OID_DESC  = "1.3.6.1.4.1.2011.6.128.1.1.2.43.1.9"   # hwGponDeviceOntDescripton
OID_SN    = "1.3.6.1.4.1.2011.6.128.1.1.2.43.1.3"   # hwGponDeviceOntSn


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
    # OID suffix apos o prefixo 2011.6.128...
    oid_tail = oid.rsplit(".", 1)[-1]  # ultimo componente numerico
    for line in out.splitlines():
        # ex: SNMPv2-SMI::enterprises.2011.6.128.1.1.2.43.1.9.X.Y.Z = STRING: "desc"
        m = re.search(r"2011\.6\.128\.\S+\." + re.escape(oid_tail) + r"\.(\S+)\s*=\s*(.+)", line)
        if not m:
            # fallback generico
            m = re.search(r"\." + re.escape(oid_tail) + r"\.(\S+)\s*=\s*(.+)", line)
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
    m = re.search(r'Hex-STRING:\s*([\dA-Fa-f\s]+)', raw)
    if m:
        bytes_hex = m.group(1).strip().split()
        try:
            ascii_part = "".join(chr(int(b, 16)) if 32 <= int(b, 16) < 127 else ""
                                 for b in bytes_hex[:4])
            hex_part   = "".join(b.upper() for b in bytes_hex[4:])
            return ascii_part + hex_part
        except Exception:
            return m.group(1).strip().replace(" ", "")
    return parse_string(raw)


# Coletar descricoes
desc_map = {}
for idx, raw in snmpwalk(OID_DESC):
    desc_map[idx] = parse_string(raw)

if not desc_map:
    print(json.dumps({"data": []}))
    sys.exit(0)

# Coletar SNs
sn_raw = {idx: raw for idx, raw in snmpwalk(OID_SN)}

# Montar LLD (filtro aplicado pelo Zabbix via {$ONU_DEDICADO_FILTER.NETSTREAM})
lld = []
for idx, desc in sorted(desc_map.items(), key=lambda x: x[0]):
    sn = parse_sn(sn_raw.get(idx, "")) if idx in sn_raw else ""
    lld.append({
        "{#NETSTREAM.ONU_DESC}":  desc,
        "{#NETSTREAM.ONU_INDEX}": idx,
        "{#SNMPINDEX}":           idx,
        "{#NETSTREAM.ONU_SN}":   sn,
    })

print(json.dumps({"data": lld}))
