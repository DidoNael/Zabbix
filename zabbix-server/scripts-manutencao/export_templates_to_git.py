#!/usr/bin/env python3
# export_templates_to_git.py
#
# Exporta templates customizados do Zabbix e salva na estrutura do repositório git.
# Deve ser rodado no servidor (ou onde o ZABBIX_API_URL seja acessível).
#
# Uso:
#   python3 export_templates_to_git.py --list            # lista todos os templates
#   python3 export_templates_to_git.py --export          # exporta os mapeados abaixo
#   python3 export_templates_to_git.py --export --all    # exporta todos os templates
#
# Saída: arquivos XML salvos em /tmp/zabbix_export/ (copiar para o repo git)

import json
import os
import re
import sys
import argparse
from datetime import datetime

try:
    from urllib.request import urlopen, Request
    from urllib.error import URLError
except ImportError:
    from urllib2 import urlopen, Request, URLError

ZABBIX_API_URL = os.getenv("ZABBIX_API_URL", "http://localhost/zabbix/api_jsonrpc.php")
ZABBIX_USER    = os.getenv("ZABBIX_USER", "Admin")
ZABBIX_PASSWORD= os.getenv("ZABBIX_PASSWORD", "zabbix")

# Mapeamento: nome do template (substring) → caminho no repo
# Formato: "parte do nome" → (diretório relativo 4.4, diretório relativo 6.0)
TEMPLATE_MAP = {
    "OLT ZTE - NETSTREAM":                    ("OLT/ZTE",          None),
    "OLT FIBERHOME":                           ("OLT/Fiberhome",    None),
    "Fiberhome":                               ("OLT/Fiberhome",    None),
    "FIBERHOME":                               ("OLT/Fiberhome",    None),
    "OLT Fiberhome":                           ("OLT/Fiberhome",    None),
    "Template Switch Huawei 6700":             ("Switch/Huawei",    None),
    "Huawei":                                  ("Switch/Huawei",    None),
    "HUAWEI":                                  ("Switch/Huawei",    None),
    "OLT HUAWEI":                              ("OLT/Huawei",       None),
    "MA5800":                                  ("OLT/Huawei",       None),
    "NETSTREAM":                               ("NETSTREAM",        None),
}

# Templates do Zabbix (built-in) a ignorar
BUILTIN_PREFIXES = [
    "Template Module",
    "Template App",
    "Template DB",
    "Template Net",
    "Template OS",
    "Template Server",
    "Linux",
    "Windows",
    "Generic",
    "ICMP",
]

OUTPUT_DIR = os.getenv("EXPORT_DIR", "/tmp/zabbix_export")


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", file=sys.stderr)


def api_call(url, method, params, auth=None):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }
    if auth:
        payload["auth"] = auth

    data = json.dumps(payload).encode("utf-8")
    req = Request(url, data=data, headers={"Content-Type": "application/json-rpc"})

    try:
        resp = urlopen(req, timeout=60)
        result = json.loads(resp.read().decode("utf-8"))
    except (URLError, Exception) as e:
        log(f"ERRO na API: {e}")
        sys.exit(1)

    if "error" in result:
        raise RuntimeError(result["error"])

    return result["result"]


def login(url, user, password):
    return api_call(url, "user.login", {"user": user, "password": password})


def logout(url, auth):
    try:
        api_call(url, "user.logout", [], auth)
    except Exception:
        pass


def get_all_templates(url, auth):
    """Lista todos os templates com contagem de hosts."""
    return api_call(url, "template.get", {
        "output": ["templateid", "name", "description"],
        "selectHosts": ["hostid"],
        "sortfield": "name",
    }, auth)


def get_zabbix_version(url, auth):
    """Detecta a versão do Zabbix."""
    info = api_call(url, "apiinfo.version", {})
    return info  # e.g. "4.4.10" or "6.0.2"


def export_template(url, auth, templateid, template_name, version_str):
    """Exporta um template como XML."""
    # Formato de export difere entre 4.4 e 6.0
    major = int(version_str.split(".")[0])
    minor = int(version_str.split(".")[1])

    if major >= 5 or (major == 4 and minor >= 4):
        # 4.4+
        result = api_call(url, "configuration.export", {
            "format": "xml",
            "options": {
                "templates": [templateid],
            },
        }, auth)
    else:
        result = api_call(url, "configuration.export", {
            "format": "xml",
            "options": {
                "templates": [templateid],
            },
        }, auth)

    return result  # XML string


def is_builtin(template_name):
    """Verifica se parece um template built-in do Zabbix."""
    for prefix in BUILTIN_PREFIXES:
        if template_name.startswith(prefix):
            return True
    return False


def find_repo_path(template_name):
    """Determina o diretório do repo para este template."""
    for keyword, (path, _) in TEMPLATE_MAP.items():
        if keyword.lower() in template_name.lower():
            return path
    return None


def sanitize_filename(name):
    """Converte nome de template em nome de arquivo seguro."""
    return re.sub(r'[^a-zA-Z0-9_-]', '_', name)


def main():
    parser = argparse.ArgumentParser(description="Exporta templates do Zabbix para o repo git")
    parser.add_argument("--list", action="store_true", help="Lista todos os templates")
    parser.add_argument("--export", action="store_true", help="Exporta templates mapeados")
    parser.add_argument("--all", action="store_true", help="Com --export: exporta todos (não só os mapeados)")
    parser.add_argument("--name", help="Com --export: filtra por substring do nome")
    args = parser.parse_args()

    if not args.list and not args.export:
        parser.print_help()
        sys.exit(1)

    log("Conectando ao Zabbix...")
    auth = login(ZABBIX_API_URL, ZABBIX_USER, ZABBIX_PASSWORD)
    version = get_zabbix_version(ZABBIX_API_URL, auth)
    log(f"Zabbix versão: {version}")

    try:
        templates = get_all_templates(ZABBIX_API_URL, auth)
        log(f"{len(templates)} templates encontrados no servidor")

        if args.list:
            print(f"\n{'ID':<10} {'Hosts':<6} {'Em repo?':<10} {'Nome'}")
            print("-" * 80)
            for t in templates:
                in_repo = "SIM" if find_repo_path(t["name"]) else ("built-in" if is_builtin(t["name"]) else "NÃO")
                host_count = len(t.get("hosts", []))
                print(f"{t['templateid']:<10} {host_count:<6} {in_repo:<10} {t['name']}")
            return

        if args.export:
            os.makedirs(OUTPUT_DIR, exist_ok=True)
            exported = 0
            skipped = 0

            for t in templates:
                name = t["name"]
                host_count = len(t.get("hosts", []))

                if args.name and args.name.lower() not in name.lower():
                    continue

                if not args.all:
                    repo_path = find_repo_path(name)
                    if not repo_path:
                        skipped += 1
                        continue
                    if is_builtin(name) and not args.name:
                        skipped += 1
                        continue
                else:
                    if is_builtin(name) and not args.name:
                        skipped += 1
                        continue
                    repo_path = find_repo_path(name) or "OUTROS"

                log(f"Exportando '{name}' ({host_count} hosts) → {repo_path}/...")

                try:
                    xml = export_template(ZABBIX_API_URL, auth, t["templateid"], name, version)

                    # Salva em subdirs por versão do Zabbix detectada
                    major_minor = ".".join(version.split(".")[:2])
                    out_subdir = os.path.join(OUTPUT_DIR, repo_path, major_minor)
                    os.makedirs(out_subdir, exist_ok=True)
                    out_file = os.path.join(out_subdir, "Template.xml")

                    with open(out_file, "w", encoding="utf-8") as f:
                        f.write(xml)

                    log(f"  Salvo em: {out_file}")
                    exported += 1

                except RuntimeError as e:
                    log(f"  ERRO ao exportar '{name}': {e}")

            log(f"\nExportados: {exported} | Ignorados: {skipped}")
            log(f"Arquivos salvos em: {OUTPUT_DIR}")
            log("")
            log("PRÓXIMOS PASSOS:")
            log(f"  1. Copiar os XMLs de {OUTPUT_DIR} para o repositório git")
            log("  2. git add . && git commit -m 'feat: adicionar templates Fiberhome/Huawei ao repo'")
            log("  3. git push")

    except RuntimeError as e:
        log(f"ERRO: {e}")
        sys.exit(1)
    finally:
        logout(ZABBIX_API_URL, auth)


if __name__ == "__main__":
    main()
