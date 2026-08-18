# Provisionamento via cloud-init (VM)

Sobe uma VM Debian 13 com Zabbix 7.0 + Nginx + PostgreSQL **já instalados no primeiro boot**,
reutilizando os mesmos `gerar-senhas.sh` e `install.sh`. Ideal para Proxmox, nuvem (AWS/OpenStack),
VMware ou seed local (NoCloud).

> Use a imagem **cloud** oficial do Debian 13 (`debian-13-genericcloud-amd64`), que já traz
> `cloud-init`. Não use a ISO de desktop/netinst comum.

Antes de usar, edite [`user-data`](user-data): `hostname`, `fqdn`, `timezone` e, se quiser, sua chave SSH.

---

## Proxmox VE

```bash
# 1) Baixe a imagem cloud e crie a VM
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
qm create 9000 --name zabbix --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 debian-13-genericcloud-amd64.qcow2 local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0

# 2) Aponte o cloud-init para este user-data (via snippet)
#    Copie user-data para /var/lib/vz/snippets/zabbix-user-data.yaml
qm set 9000 --cicustom "user=local:snippets/zabbix-user-data.yaml"
qm set 9000 --ipconfig0 ip=dhcp
qm resize 9000 scsi0 +8G
qm start 9000
```

Ajuste também o IP/DNS pela aba **Cloud-Init** da VM no Proxmox, se preferir IP fixo.

---

## NoCloud (seed ISO — VMware/VirtualBox/KVM local)

Gere um ISO de seed com `user-data` e `meta-data` e anexe como segundo CD-ROM:

```bash
cloud-localds seed.iso user-data meta-data     # pacote cloud-image-utils
# ou:
genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
```

Suba a VM com a imagem cloud do Debian 13 como disco e `seed.iso` como CD — o cloud-init lê o seed no boot.

---

## Nuvem (AWS/OpenStack)

Cole o conteúdo de `user-data` no campo **User data** ao criar a instância (Debian 13). O `meta-data`
é fornecido pela própria plataforma.

---

## Após o boot

1. Acesse `http://<IP-da-VM>/` → login `Admin` / `zabbix`.
2. Recupere as senhas geradas:
   ```bash
   sudo cat /opt/zabbix-setup/zabbix-server/setup-zabbix-nginx-pgsql/.env
   ```
   Guarde no cofre e **troque a senha do Admin** no frontend.
3. Rode o firewall só depois de confirmar o acesso:
   ```bash
   sudo MGMT_NET="10.0.0.0/8" /opt/zabbix-setup/zabbix-server/setup-zabbix-nginx-pgsql/seguranca/firewall.sh
   ```
4. Logs do provisionamento: `sudo cat /var/log/cloud-init-output.log`.

> **Segurança:** as senhas aparecem em `/var/log/cloud-init-output.log`. Em ambientes sensíveis,
> limpe esse log após guardar as credenciais: `sudo truncate -s0 /var/log/cloud-init-output.log`.
