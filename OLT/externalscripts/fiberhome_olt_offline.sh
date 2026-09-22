#!/bin/bash
status_ont=$(snmpbulkwalk -v 2c -t 5 -r 1 -c $1 $2 .1.3.6.1.4.1.5875.800.3.10.1.1.11  | grep 'INTEGER: 0' | wc -l)
echo $status_ont;


