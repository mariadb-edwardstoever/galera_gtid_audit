# galera_gtid_watch
### Records the GTID of Galera nodes once per minute so that a remote slave can be switched to a different Galera node as master.

Review and edit the file create_objects.sql to meet your needs. You will need to install the MariaDB Spider Plugin on the slave.

Once the objects have been created, you will have tables that will compare the local gtid_slave_pos with the remote gtid_binlog_pos on each Galera node. The comparison will be less valid if the slave is frequently behind the master.

A quick example is seen here on the replica/slave:
```sql
MariaDB [galera_spider]> select tick, slave_running as running, m1_gtid_binlog_pos,
    -> local_gtid_slave_pos, seqno_offset from V_M1_COMPARE order by tick desc limit 3;
+---------------------+---------+--------------------------+--------------------------+---------------------+
| tick                | running | m1_gtid_binlog_pos       | local_gtid_slave_pos     | seqno_offset        |
+---------------------+---------+--------------------------+--------------------------+---------------------+
| 2023-08-08 19:28:30 | ON      | 0-1-294171,77-1-2,88-1-2 | 0-1-294171,77-1-2,88-1-2 | GTIDs ARE IDENTICAL |
| 2023-08-08 19:27:30 | ON      | 0-1-294077,77-1-2,88-1-2 | 0-1-294077,77-1-2,88-1-2 | GTIDs ARE IDENTICAL |
| 2023-08-08 19:26:30 | ON      | 0-1-293985,77-1-2,88-1-2 | 0-1-293985,77-1-2,88-1-2 | GTIDs ARE IDENTICAL |
+---------------------+---------+--------------------------+--------------------------+---------------------+
3 rows in set (0.001 sec)

MariaDB [galera_spider]> select tick, slave_running as running, m3_gtid_binlog_pos,
    -> local_gtid_slave_pos, seqno_offset from V_M3_COMPARE order by tick desc limit 3;
+---------------------+---------+--------------------+--------------------------+----------------------+
| tick                | running | m3_gtid_binlog_pos | local_gtid_slave_pos     | seqno_offset         |
+---------------------+---------+--------------------+--------------------------+----------------------+
| 2023-08-08 19:28:30 | ON      | 0-1-294176         | 0-1-294171,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
| 2023-08-08 19:27:30 | ON      | 0-1-294082         | 0-1-294077,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
| 2023-08-08 19:26:30 | ON      | 0-1-293990         | 0-1-293985,77-1-2,88-1-2 | DOMAIN: 0 OFFSET: +5 |
+---------------------+---------+--------------------+--------------------------+----------------------+
3 rows in set (0.001 sec)
```
In this example, we see that the slave has identical gtids as the node m1. We know that m1 is currently the master.

Next, we see that the the gtid on node m3 has a consistent offset of +5. This means three things:
- The slave is up-to-date with the Galera cluster, in other words 0 seconds behing master. 
- If we want to switch masters from m1 to m3, we need to adjust the seq_no position of GTID +5.
- Only domain 0 matters. We can ignore gtids from domains 77 and 88.

Always select from the view that represents the node you want to SWITCH to in order to get the correct offset. Sometimes, the GTIDs will be identical in which case, you need not change the gtid_slave_pos.
```sql
MariaDB [galera_spider]> stop slave;
Query OK, 0 rows affected (0.008 sec)

MariaDB [galera_spider]> show global variables like 'gtid_slave_pos';
+----------------+--------------------------+
| Variable_name  | Value                    |
+----------------+--------------------------+
| gtid_slave_pos | 0-1-294879,77-1-2,88-1-2 |
+----------------+--------------------------+
1 row in set (0.001 sec)

MariaDB [galera_spider]> change master to master_host='192.168.8.189';
Query OK, 0 rows affected (0.009 sec)

MariaDB [galera_spider]> set global gtid_slave_pos='0-1-294884';
Query OK, 0 rows affected (0.006 sec)

MariaDB [galera_spider]> start slave;
Query OK, 0 rows affected (0.011 sec)

MariaDB [galera_spider]> show slave status\G  --- 
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.8.189
                   Using_Gtid: Slave_Pos
                   Gtid_IO_Pos: 0-1-295072
                 Parallel_Mode: optimistic
                     SQL_Delay: 0
           SQL_Remaining_Delay: NULL
       Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates

MariaDB [galera_spider]> select tick, slave_running as running, m3_gtid_binlog_pos,
    -> local_gtid_slave_pos, seqno_offset from V_M3_COMPARE order by tick desc limit 3;
+---------------------+---------+--------------------+----------------------+---------------------+
| tick                | running | m3_gtid_binlog_pos | local_gtid_slave_pos | seqno_offset        |
+---------------------+---------+--------------------+----------------------+---------------------+
| 2023-08-08 19:42:30 | ON      | 0-1-295476         | 0-1-295476           | GTIDs ARE IDENTICAL |
| 2023-08-08 19:41:30 | ON      | 0-1-295384         | 0-1-295384           | GTIDs ARE IDENTICAL |
| 2023-08-08 19:40:30 | ON      | 0-1-295292         | 0-1-295292           | GTIDs ARE IDENTICAL |
+---------------------+---------+--------------------+----------------------+---------------------+
3 rows in set (0.001 sec)
```

### How should my Galera be set up for this?
There is nothing special in Galera to make this work. I do not use WSREP_GTID_MODE for this to work. I use the following global variables on each Galera node:
```
# server_id (not set)
# gtid_domain_id (not set)
# wsrep_gtid_mode (not set)
# wsrep_gtid_domain_id (not set)
# gtid_domain_id (not set)
# server_id (not set) # it is possible to have each Galera node with a 
                      # different server_id. But, it will add a step when switching masters.
binlog_format = ROW   # Necessary for Galera. Understand the consequences for the replica/slave.
```
### What is the extra step if each Galera node has a different server_id?
Let's say you determine you want to switch nodes, and the start is at seq_no 290112. You need to either guess the server_id for that sequence, or get it from one of the binary logs shown here. By the way, if you guess the server_id and fail, you can try again, there are only 3 possibilities for a three-node cluster. Anyway, here we see how to do it:
```
# Look for GTID with seq_no 290112 to get the server_id
root@m1:~$ mariadb-binlog /var/log/mysql/mariadb-bin-log.000017 |grep 290112| grep GTID
#230808 14:32:11 server id 2  end_log_pos 6065460 CRC32 0x4b5fb18c      GTID 0-2-290112 trans
root@m1:~$
```
In this case, server_id is 2.

## What if the Galera node that is acting as Primary/Master crashed a few hours ago?
If the Primary/Master has crashed and you want to switch the slave to an alternative, all you need to do is review the last moment that the slave was running = ON. Here is an example where we want to switch the slave from m3 (crashed) to m1:
```sql
MariaDB [galera_spider]> select tick, slave_running as running, m1_gtid_binlog_pos,
    -> local_gtid_slave_pos, seqno_offset from V_M1_COMPARE
    -> where slave_running='ON' order by tick desc limit 3;
+---------------------+---------+--------------------------+----------------------+----------------------+
| tick                | running | m1_gtid_binlog_pos       | local_gtid_slave_pos | seqno_offset         |
+---------------------+---------+--------------------------+----------------------+----------------------+
| 2023-08-08 19:56:30 | ON      | 0-1-296773,77-1-2,88-1-2 | 0-1-296778           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 19:55:30 | ON      | 0-1-296679,77-1-2,88-1-2 | 0-1-296684           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 19:54:30 | ON      | 0-1-296587,77-1-2,88-1-2 | 0-1-296592           | DOMAIN: 0 OFFSET: -5 |
+---------------------+---------+--------------------------+----------------------+----------------------+
3 rows in set (0.001 sec)

```
If you are curious, the very next tick should be running OFF and the seqno_offset should increase quickly:
```sql
MariaDB [galera_spider]> select tick, slave_running as running, m1_gtid_binlog_pos,
    -> local_gtid_slave_pos, seqno_offset from V_M1_COMPARE
    -> where tick > '2023-08-08 19:56:30'  order by tick asc limit 3;
+---------------------+---------+--------------------------+----------------------+------------------------+
| tick                | running | m1_gtid_binlog_pos       | local_gtid_slave_pos | seqno_offset           |
+---------------------+---------+--------------------------+----------------------+------------------------+
| 2023-08-08 19:57:30 | OFF     | 0-1-296839,77-1-2,88-1-2 | 0-1-296790           | DOMAIN: 0 OFFSET: +49  |
| 2023-08-08 19:58:30 | OFF     | 0-1-296900,77-1-2,88-1-2 | 0-1-296790           | DOMAIN: 0 OFFSET: +110 |
| 2023-08-08 19:59:30 | OFF     | 0-1-296963,77-1-2,88-1-2 | 0-1-296790           | DOMAIN: 0 OFFSET: +173 |
+---------------------+---------+--------------------------+----------------------+------------------------+
3 rows in set (0.001 sec)
```
We want to resume from the current position using the correct offset which was -5 when the slave was last running. Ignore offsets that increase or decrease each minute which come from the slave running behind master, or catching up to master, or a failure as it is in this case.
```sql
MariaDB [galera_spider]> stop slave;
Query OK, 0 rows affected (0.007 sec)

MariaDB [galera_spider]> show global variables like 'gtid_slave_pos';
+----------------+------------+
| Variable_name  | Value      |
+----------------+------------+
| gtid_slave_pos | 0-1-296790 |
+----------------+------------+
1 row in set (0.000 sec)

MariaDB [galera_spider]> change master to master_host='192.168.8.187';
Query OK, 0 rows affected (0.010 sec)

MariaDB [galera_spider]> set global gtid_slave_pos='0-1-296785';
Query OK, 0 rows affected (0.009 sec)

MariaDB [galera_spider]> start slave;
Query OK, 0 rows affected (0.010 sec)

MariaDB [galera_spider]> show slave status\G
*************************** 1. row ***************************
                Slave_IO_State: Waiting for master to send event
                   Master_Host: 192.168.8.187
                   Gtid_IO_Pos: 77-1-2,88-1-2,0-1-298734
                     SQL_Delay: 0
           SQL_Remaining_Delay: NULL
       Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates
```
Checking values on tables that are active prove the slave is lined up properly with the Galera cluster. Now you can work on bringing back the crashed node.

## What if my replica/slave is also a master in a chain of nodes? 
If your replica/slave is in a chain of replicas and you don't want to replicate down the chain, you can create the objects with `set session sql_log_bin=OFF;` 
Next, you can set up an exception with the global `replicate_ignore_db='galera_spider'`. See this page:
https://mariadb.com/kb/en/replication-and-binary-log-system-variables/
