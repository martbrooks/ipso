#!/bin/bash

psql ipso -f ipso_schema.sql

./ipso_block -a 192.168.0.0/24 -n 'Part of RFC1918'
./ipso_block -a 192.168.1.0/24 -n 'Part of RFC1918'
./ipso_block -a 10.0.0.0/8 -n 'Also part of RFC1918'
./ipso_block -a 2001:ba8:1f1:f12c::/64 -n 'Some IPv6'

psql ipso -f ipso_bootstrap.sql
