ipso
====

An IP address management tool in development.

To get started you will need to have a PostgreSQL server up and running.  It
works with 9.3.3 and will probably work with earlier 9.x series releases.

At the moment, you are assumed to be using the following database settings:

    server: localhost
    database: ipso
    username: ipso
    password: ipso

As a postgres superuser, or user with suitable rights, you might:

    createuser ipso
    createdb -O ipso ipso

Initialise the database and sample data with:

    psql ipso -f ipso.sql

If you're using Debian or Ubuntu, install the following packages:

    libdbd-pg-perl
    libgetopt-long-descriptive-perl
    libnetaddr-ip-perl
    libregexp-common-net-cidr-perl
    libregexp-common-perl
    libregexp-ipv6-perl
    libswitch-perl
    libtext-asciitable-perl

You may then be able to do the following:

martin@molly:~/ipso$ ./ipso_block -l
.---------------------------------------------------------------------------------------------------------------------.
|                                                 Available IP Blocks                                                 |
+----+------------------------+-------------+--------------------+-----------------------------+----------------------+
| ID | Block                  | Allocations | Used (%)           | Free (%)                    | Notes                |
+----+------------------------+-------------+--------------------+-----------------------------+----------------------+
|  1 | 192.168.0.0/24         |           2 | 40 (15.6%)         | 216 (84.4%)                 | Part of RFC1918      |
|  2 | 192.168.1.0/24         |           2 | 40 (15.6%)         | 216 (84.4%)                 | Part of RFC1918      |
|  3 | 10.0.0.0/8             |           1 | 10 (5.96e-05%)     | 16777206 (100%)             | Also part of RFC1918 |
|  4 | 2001:ba8:1f1:f12c::/64 |           1 | 100000 (5.42e-13%) | 1.84467440737095e+19 (100%) | Some IPv6            |
'----+------------------------+-------------+--------------------+-----------------------------+----------------------'

