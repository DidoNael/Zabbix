#!/bin/bash

# Defina o IP do MikroTik e o site como variáveis
mikrotik_ip=$1
site=$2

# Executa o comando traceroute no MikroTik e captura a saída
output=$(ssh zabbix@"$mikrotik_ip" "/tool traceroute address=$site count=2 size=128; quit")

# Processa a saída para formatar em JSON, capturando apenas o último resultado de cada salto e removendo "ms"
echo "$output" | awk '
BEGIN {
    print "{ \"traceroute\": ["
}
{
    if (NR > 1 && $1 ~ /^[0-9]+$/) {
        hop = $1
        last = $5
        best = $6
        worst = $7
        
        gsub(/ms/, "", last)
        gsub(/ms/, "", best)
        gsub(/ms/, "", worst)

        if (last != "" && best != "" && worst != "") {
            hop_line[hop] = sprintf("  { \"hop\": %d, \"address\": \"%s\", \"loss\": \"%s\", \"sent\": %s, \"last\": \"%s\", \"avg\": \"%s\", \"best\": \"%s\", \"worst\": \"%s\" }", $1, $2, $3, $4, last, last, best, worst)

            if (!(hop in min_best) || (best != "" && best < min_best[hop])) {
                min_best[hop] = best
            }
            if (!(hop in max_worst) || (worst != "" && worst > max_worst[hop])) {
                max_worst[hop] = worst
            }
        }
    }
}
END {
    first = 1
    for (i = 1; i <= length(hop_line); i++) {
        if (hop_line[i] != "") {
            if (!first) {
                print ","
            }
            first = 0
            gsub(/\"best\": \"[^\"]*\"/, "\"best\": \"" min_best[i] "\"", hop_line[i])
            gsub(/\"worst\": \"[^\"]*\"/, "\"worst\": \"" max_worst[i] "\"", hop_line[i])
            print hop_line[i]
        }
    }
    print "] }"
}
'
