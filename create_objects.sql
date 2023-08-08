/* THIS SQL DOCUMENT CONTAINS COMMANDS FOR CREATING A SCHEMA galera_spider AND THE OBJECTS NECESSARY TO SUPPORT GALERA GTID WATCH */
/* THE SCHEMA galera_spider will contain: TABLES, VIEWS, PROCEDURES, FUNCTIONS, and EVENTS. */
/*  Object ownership should be by a user with SUPER privileges such as `root`@`localhost` */
/* DO NOT RUN THIS FILE IN ONE RUN. IT IS INTENEDED TO BE USED AS A MODEL FOR CREATING OBJECTS. */
/* EDIT EACH COMMAND IN THE FILE AND COPY PASTE OBJECT DEFINITIONS ONE AT A TIME */

/* GALERA GTID WATCH REQUIRES THE MARIADB SPIDER PLUGIN ON THE REPLICA/SLAVE ONLY */
/* DOCUMENTATION: https://mariadb.com/kb/en/spider-installation/     */
/* The command on Debian to install is: apt install mariadb-plugin-spider */
/* If you like to use the scprit mariadb-install-db to create a new empty */
/* instance keep in mind the following: */
/*  ● If mariadb-plugin-spider is already installed, remove/uninstall it before mariadb-install-db. */
/*  ● Some global options in .cnf files can prevent mariadb-install-db from completing. Move custom .cnf files to /tmp directory. */
 
/* Ref CS0621875 */

-- ensure that SPIDER plugin is correctly installed:
SELECT ENGINE, SUPPORT FROM information_schema.ENGINES WHERE ENGINE = 'SPIDER';
/*
+--------+---------+
| ENGINE | SUPPORT |
+--------+---------+
| SPIDER | YES     |
+--------+---------+
1 row in set (0.000 sec)
*/



/*
--- YOU WILL NEED THE FOLLOWING USERS CREATED ON THE GALERA CLUSTER (USE ANY NODE) 
CREATE USER `spider`@`192.168.8.217` IDENTIFIED BY 'passwd';
-- THE SPIDER USER WILL ONLY SELECT ON information_schema.GLOBAL_VARIABLES and does not need any privileges for that
CREATE USER `repl`@`192.168.8.217` IDENTIFIED BY 'passwd';
GRANT REPLICATION SLAVE ON *.* TO `repl`@`192.168.8.217`;
*/

/*
Example topology:
HOST          IP                 ROLE
m1.edw.ee     192.168.8.187      Galera node 1
m2.edw.ee     192.168.8.188      Galera node 2
m3.edw.ee     192.168.8.189      Galera node 3
EE106.edw.ee  192.168.8.217      Replica
*/

-- The following commands MUST BE EDITED and run on the REPLICA/SLAVE:
CREATE SERVER m1 FOREIGN DATA WRAPPER mysql
OPTIONS (HOST '192.168.8.187',DATABASE 'information_schema', USER 'spider', PASSWORD 'passwd', PORT 3306);
CREATE SERVER m2 FOREIGN DATA WRAPPER mysql
OPTIONS (HOST '192.168.8.188',DATABASE 'information_schema', USER 'spider', PASSWORD 'passwd', PORT 3306);
CREATE SERVER m3 FOREIGN DATA WRAPPER mysql
OPTIONS (HOST '192.168.8.189',DATABASE 'information_schema', USER 'spider', PASSWORD 'passwd', PORT 3306);


/* The galera_spider schema only exists on the REPLICA/SLAVE */
create schema galera_spider;
use galera_spider;
drop table if exists m1_global_variables; 
drop table if exists m2_global_variables; 
drop table if exists m3_global_variables;

-- EACH OF THE THREE FOLLOWING CREATE TABLE COMMANDS NEEDS TO BE EDITED 
-- IF YOU DO NOT USE m1, m2, m3 as SERVER name in PREVIOUS COMMANDS
CREATE TABLE m1_global_variables (
  `VARIABLE_NAME` varchar(64) NOT NULL,
  `VARIABLE_VALUE` varchar(2048) NOT NULL
) ENGINE=Spider
COMMENT='wrapper "mysql", srv "m1", table "GLOBAL_VARIABLES"';

CREATE TABLE m2_global_variables (
  `VARIABLE_NAME` varchar(64) NOT NULL,
  `VARIABLE_VALUE` varchar(2048) NOT NULL
) ENGINE=Spider
COMMENT='wrapper "mysql", srv "m2", table "GLOBAL_VARIABLES"';

CREATE TABLE m3_global_variables (
  `VARIABLE_NAME` varchar(64) NOT NULL,
  `VARIABLE_VALUE` varchar(2048) NOT NULL
) ENGINE=Spider
COMMENT='wrapper "mysql", srv "m3", table "GLOBAL_VARIABLES"';



/* A QUICK OVERVIEW OF TRANSFERRING THE SCHEMAS FROM Galera node m1 to Slave
ON m1 Galera server:
mariadb-dump --all-databases --master-data=2 --gtid --routines --events --ignore-table=mysql.proc > m1.dump.sql
scp m1.dump.sql root@192.168.8.217:~/

On slave:
mariadb < m1.dump.sql
head -30 m1.dump.sql | grep gtid
-- SET GLOBAL gtid_slave_pos='0-1-1054';

stop slave; 
reset slave; 
set global gtid_slave_pos='0-1-1054'; 
change master to master_host='192.168.8.187', master_port=3306, master_user='repl', master_password='passwd', master_use_gtid=slave_pos; 
start slave;
*/

use galera_spider;
drop table if exists `m1_gtid_compare`;
CREATE TABLE `m1_gtid_compare` (
  `tick` datetime DEFAULT NULL,
  `m1_gtid_binlog_pos` varchar(256) DEFAULT NULL,
  `local_gtid_slave_pos` varchar(256) DEFAULT NULL,
  `slave_running` varchar(10)  DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

drop table if exists `m2_gtid_compare`;
CREATE TABLE `m2_gtid_compare` (
  `tick` datetime DEFAULT NULL,
  `m2_gtid_binlog_pos` varchar(256) DEFAULT NULL,
  `local_gtid_slave_pos` varchar(256) DEFAULT NULL,
  `slave_running` varchar(10)  DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

drop table if exists `m3_gtid_compare`;
CREATE TABLE `m3_gtid_compare` (
  `tick` datetime DEFAULT NULL,
  `m3_gtid_binlog_pos` varchar(256) DEFAULT NULL,
  `local_gtid_slave_pos` varchar(256) DEFAULT NULL,
  `slave_running` varchar(10)  DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


use galera_spider;
delimiter //
CREATE OR REPLACE PROCEDURE `P_M1_GALERA_GTID_CHECK`()
LANGUAGE SQL NOT DETERMINISTIC CONTAINS SQL SQL SECURITY DEFINER
COMMENT 'Created By Edward Stoever for Mariadb Support Ref: CS0621875'
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    insert into m1_gtid_compare
    select now(),'error', lo.VARIABLE_VALUE, li.VARIABLE_VALUE
    from  information_schema.global_variables as lo JOIN information_schema.global_status as li
    where lo.VARIABLE_NAME='GTID_SLAVE_POS'
    and li.VARIABLE_NAME='SLAVE_RUNNING';
  END;
-- The following is done when no error:
  insert into m1_gtid_compare
  select now(),m1.VARIABLE_VALUE , lo.VARIABLE_VALUE, li.VARIABLE_VALUE
  from m1_global_variables as m1 
  JOIN information_schema.global_variables as lo 
  JOIN information_schema.global_status as li
  where m1.VARIABLE_NAME='GTID_BINLOG_POS' and lo.VARIABLE_NAME='GTID_SLAVE_POS'
  and li.VARIABLE_NAME='SLAVE_RUNNING';
END;
//
delimiter ;

use galera_spider;
delimiter //
CREATE OR REPLACE PROCEDURE `P_M2_GALERA_GTID_CHECK`()
LANGUAGE SQL NOT DETERMINISTIC CONTAINS SQL SQL SECURITY DEFINER
COMMENT 'Created By Edward Stoever for Mariadb Support Ref: CS0621875'
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN 
    insert into m2_gtid_compare
    select now(),'error', lo.VARIABLE_VALUE, li.VARIABLE_VALUE
    from  information_schema.global_variables as lo JOIN information_schema.global_status as li
    where lo.VARIABLE_NAME='GTID_SLAVE_POS'
    and li.VARIABLE_NAME='SLAVE_RUNNING';
  END;
-- The following is done when no error:
  insert into m2_gtid_compare
  select now(),m2.VARIABLE_VALUE , lo.VARIABLE_VALUE, li.VARIABLE_VALUE
  from m2_global_variables as m2
  JOIN information_schema.global_variables as lo 
  JOIN information_schema.global_status as li
  where m2.VARIABLE_NAME='GTID_BINLOG_POS' and lo.VARIABLE_NAME='GTID_SLAVE_POS'
  and li.VARIABLE_NAME='SLAVE_RUNNING';
END;
//
delimiter ;


use galera_spider;
delimiter //
CREATE OR REPLACE PROCEDURE `P_M3_GALERA_GTID_CHECK`()
LANGUAGE SQL NOT DETERMINISTIC CONTAINS SQL SQL SECURITY DEFINER
COMMENT 'Created By Edward Stoever for Mariadb Support Ref: CS0621875'
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    insert into m3_gtid_compare
    select now(),'error', lo.VARIABLE_VALUE, li.VARIABLE_VALUE
    from  information_schema.global_variables as lo JOIN information_schema.global_status as li
    where lo.VARIABLE_NAME='GTID_SLAVE_POS'
    and li.VARIABLE_NAME='SLAVE_RUNNING';
  END;
-- The following is done when no error:
  insert into m3_gtid_compare
  select now(),m3.VARIABLE_VALUE , lo.VARIABLE_VALUE, li.VARIABLE_VALUE
  from m3_global_variables as m3 
  JOIN information_schema.global_variables as lo 
  JOIN information_schema.global_status as li
  where m3.VARIABLE_NAME='GTID_BINLOG_POS' and lo.VARIABLE_NAME='GTID_SLAVE_POS'
  and li.VARIABLE_NAME='SLAVE_RUNNING';
END;
//
delimiter ;

use galera_spider;
delimiter //
CREATE OR REPLACE PROCEDURE `P_RESET_GTID_COMPARE_TABLES`()
LANGUAGE SQL NOT DETERMINISTIC CONTAINS SQL SQL SECURITY DEFINER
COMMENT 'Created By Edward Stoever for Mariadb Support Ref: CS0621875'
BEGIN
  TRUNCATE TABLE m1_gtid_compare;
  TRUNCATE TABLE m2_gtid_compare;
  TRUNCATE TABLE m3_gtid_compare;
END;
//
delimiter ;

use galera_spider;
delimiter //
CREATE OR REPLACE EVENT `EV_GALERA_GTID_CHECK`
	ON SCHEDULE EVERY 1 MINUTE 
	STARTS cast(date_format(now() + interval 1 minute,'%Y-%m-%d %H:%i:30') as datetime)
	ON COMPLETION PRESERVE ENABLE
	COMMENT 'Created By Edward Stoever for Mariadb Support Ref: CS0621875'
DO BEGIN
  CALL P_M1_GALERA_GTID_CHECK();
  CALL P_M2_GALERA_GTID_CHECK();
  CALL P_M3_GALERA_GTID_CHECK();
END;
//
delimiter ;

use galera_spider;
delimiter //
create or replace function F_GTIDS_OFFSET(gtid_1 varchar(500), gtid_2 varchar(500))
returns varchar(1500)
deterministic
begin

 DECLARE remaining_gtid_1 varchar(500);
 DECLARE working_gtid_1 varchar(500); 
 DECLARE working_domain_id_1 integer;
 DECLARE working_seq_no_1 integer;

 DECLARE remaining_gtid_2 varchar(500);
 DECLARE working_gtid_2 varchar(500); 
 DECLARE working_domain_id_2 integer;
 DECLARE working_seq_no_2 integer;

 DECLARE return_string varchar(500);
 DECLARE fset integer;
 DECLARE domains_in_common integer;
 
 set remaining_gtid_1=concat(gtid_1,',');
 set return_string = '';
 set domains_in_common = 0;
 
 if instr(gtid_1,'-') = 0 then return 'error'; end if;
 if instr(gtid_2,'-') = 0 then return 'error'; end if;
 WHILE instr(remaining_gtid_1,',') > 0 DO
 set working_gtid_1 = substring_index(remaining_gtid_1, ',', 1);
 set working_domain_id_1 = substring_index(working_gtid_1,'-',1);
 set remaining_gtid_2=concat(gtid_2,','); -- must be set in first WHILE loop
   WHILE instr(remaining_gtid_2,',') > 0 DO
    set working_gtid_2 = substring_index(remaining_gtid_2, ',', 1);
    set working_domain_id_2 = substring_index(working_gtid_2,'-',1);
    IF working_domain_id_1 = working_domain_id_2 THEN
	  set domains_in_common = 1;
      set working_seq_no_1 = substring_index(working_gtid_1, '-', -1);
      set working_seq_no_2 = substring_index(working_gtid_2, '-', -1);
	  set fset = (working_seq_no_2 - working_seq_no_1);
	  if fset != 0 then
	    set return_string=concat(return_string,if(length(return_string)=0,'',', '),'DOMAIN: ',working_domain_id_1,' OFFSET: ',if(fset>1,'+',''),fset);
	  end if;
	END IF;
	set remaining_gtid_2 = mid(remaining_gtid_2, instr(remaining_gtid_2, ',') + 1);
   END WHILE;
   set remaining_gtid_1 = mid(remaining_gtid_1, instr(remaining_gtid_1, ',') + 1); 
 END WHILE;
if return_string = '' and domains_in_common = 1 then set return_string='GTIDs ARE IDENTICAL'; end if;
if return_string = '' and domains_in_common != 1 then set return_string='NO DOMAIN IN COMMON'; end if;
return return_string;
end;
//
delimiter ;


use galera_spider;
CREATE OR REPLACE VIEW V_M1_COMPARE AS 
select tick, slave_running, m1_gtid_binlog_pos,
local_gtid_slave_pos,
F_GTIDS_OFFSET(local_gtid_slave_pos, m1_gtid_binlog_pos) as `seqno_offset` 
from m1_gtid_compare
where tick > now() - interval 1 day;

CREATE OR REPLACE VIEW V_M2_COMPARE AS 
select tick, slave_running, m2_gtid_binlog_pos, 
local_gtid_slave_pos,
F_GTIDS_OFFSET(local_gtid_slave_pos, m2_gtid_binlog_pos) as `seqno_offset` 
from m2_gtid_compare
where tick > now() - interval 1 day;

CREATE OR REPLACE VIEW V_M3_COMPARE AS 
select tick, slave_running, m3_gtid_binlog_pos, 
local_gtid_slave_pos,
F_GTIDS_OFFSET(local_gtid_slave_pos, m3_gtid_binlog_pos) as `seqno_offset`  
from m3_gtid_compare
where tick > now() - interval 1 day;


select * from V_M1_COMPARE order by tick desc limit 5;
/*
+---------------------+---------------+--------------------------+----------------------+----------------------+
| tick                | slave_running | m1_gtid_binlog_pos       | local_gtid_slave_pos | seqno_offset         |
+---------------------+---------------+--------------------------+----------------------+----------------------+
| 2023-08-08 18:29:30 | ON            | 0-1-289859,77-1-2,88-1-2 | 0-1-289864           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 18:28:30 | ON            | 0-3-289769,77-1-2,88-1-2 | 0-3-289774           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 18:27:30 | ON            | 0-2-289676,77-1-2,88-1-2 | 0-2-289681           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 18:26:30 | ON            | 0-3-289583,77-1-2,88-1-2 | 0-3-289588           | DOMAIN: 0 OFFSET: -5 |
| 2023-08-08 18:25:30 | ON            | 0-2-289488,77-1-2,88-1-2 | 0-2-289493           | DOMAIN: 0 OFFSET: -5 |
+---------------------+---------------+--------------------------+----------------------+----------------------+
5 rows in set (0.001 sec)

MariaDB [galera_spider]> stop slave;
Query OK, 0 rows affected (0.007 sec)

MariaDB [galera_spider]> show global variables like 'gtid_slave_pos';
+----------------+------------+
| Variable_name  | Value      |
+----------------+------------+
| gtid_slave_pos | 0-2-290117 |
+----------------+------------+
1 row in set (0.000 sec)

-- IN THIS EXAMPLE YOU WILL HAVE TO SUBTRACT 5 FROM GTID_SEQ_NO TO MOVE SLAVE TO GALERA NODE m1
HERE IS THE GTID on m1:
THIS STEP IS NECESSARY if each GALERA server has different value for server_id, so that you can get the server_id for that txn.
root@m1:~$ mariadb-binlog /var/log/mysql/mariadb-bin-log.000017 |grep 290112| grep GTID
#230808 14:32:11 server id 2  end_log_pos 6065460 CRC32 0x4b5fb18c      GTID 0-2-290112 trans
root@m1:~$
*/

change master to master_host='192.168.8.187'; -- change from m2 to m1
set global gtid_slave_pos='0-2-290112'; -- reduce by 5 from 0-2-290117

-- Check counts on active tables, they should be precisely same on slave from any Galera host!