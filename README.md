# galera_gtid_watch
### Records the GTID of Galera nodes once per minute so that a remote slave can be switched to a different Galera node as master.

Once the objects have been created, you will have a tables that will compare the local gtid_slave_pos with the remote gtid_binlog_pos on a given Galera node. This only makes sense if the slave is 0 seconds behind master. The comparison will not valid if the slave is frequently catching up.

A quick example is seen here on the replica/slave:
```sql
MariaDB [galera_spider]> select * from V_M3_COMPARE order by tick desc limit 3;
+---------------------+---------------+--------------------+--------------------------+----------------------+
| tick                | slave_running | m3_gtid_binlog_pos | local_gtid_slave_pos     | seqno_offset         |
+---------------------+---------------+--------------------+--------------------------+----------------------+
| 2023-08-08 19:13:30 | ON            | 0-1-292781         | 0-1-292776,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
| 2023-08-08 19:12:30 | ON            | 0-1-292688         | 0-1-292683,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
| 2023-08-08 19:11:30 | ON            | 0-1-292593         | 0-1-292588,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
+---------------------+---------------+--------------------+--------------------------+----------------------+
3 rows in set (0.001 sec)

MariaDB [galera_spider]>
```

