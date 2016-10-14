SELECT last_good_date FROM DBA_AUTOTASK_TASK t WHERE client_name = 'auto optimizer stats collection';

select dbms_stats.get_prefs('STALE_PERCENT','TARGET_DW', 'USAGE_FCT' ) from dual;

select dbms_stats.get_prefs('CASCADE','TARGET_DW', 'USAGE_FCT' ) from dual;


-- get top 5 sql_ids for the period of interest
select t.*,  case when upper(sql.sql_text) like '%USAGE_FCT%' AND upper(sql.sql_text) not like '%ICT_USAGE_FCT%' then 1 else 0  END USAGE_FCT_FLAG, case when upper(sql.sql_text) like '%ICT_USAGE_FCT%' then 1 else 0  END ICT_USAGE_FCT_FLAG, sql.sql_text 
from (
select trunc(sample_time) stime, sql_id, count(*), round(sum(10)/60) mins, rank() over(partition by trunc(sample_time) order by round(sum(10)/60) desc) rank --sample_time,trunc(sample_time), (sample_time - trunc(sample_time)),interval '16' hour , interval '24' hour   --* 
from dba_hist_active_sess_history
where
module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
AND sample_time between to_date('2014-06-02','yyyy-mm-dd') and to_date('2014-06-03', 'yyyy-mm-dd') -- problem period
AND (sample_time - trunc(sample_time)) between interval '16' hour and interval '24' hour -- only within the maintenance window 16:00 to 00:00 
and user_id = 0 -- sys
group by trunc(sample_time),sql_id 
--order by 1, count(*) desc
) t, dba_hist_sqltext sql
where 
t.sql_id = sql.sql_id
and t.mins > 60 and t.sql_id is not NULL
and rank < 6
order by stime, rank

-- get the most frequent heavy query with input the previous query
select sql_id, sum(1) cnt
from (
select t.*,  case when upper(sql.sql_text) like '%USAGE_FCT%' then 1 else 0  END USAGE_FCT_FLAG, case when upper(sql.sql_text) like '%ICT_USAGE_FCT%' then 1 else 0  END ICT_USAGE_FCT_FLAG, sql.sql_text 
from (
select trunc(sample_time) stime, sql_id, count(*), round(sum(10)/60) mins, rank() over(partition by trunc(sample_time) order by round(sum(10)/60) desc) rank --sample_time,trunc(sample_time), (sample_time - trunc(sample_time)),interval '16' hour , interval '24' hour   --* 
from dba_hist_active_sess_history
where
module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
AND sample_time between to_date('2014-03-26','yyyy-mm-dd') and to_date('2014-04-17', 'yyyy-mm-dd') -- problem period
AND (sample_time - trunc(sample_time)) between interval '16' hour and interval '24' hour -- only within the maintenance window 16:00 to 00:00 
and user_id = 0 -- sys
group by trunc(sample_time),sql_id 
--order by 1, count(*) desc
) t, dba_hist_sqltext sql
where 
t.sql_id = sql.sql_id
and t.mins > 60
and t.sql_id is not NULL
and rank < 6
order by stime, rank
)
group by sql_id
order by 2 desc

-- find change of execution plan for all sql_ids of interest
select sql_id,  count(distinct plan_hash_value) --trunc(BEGIN_INTERVAL_TIME), 
from (
select    a.INSTANCE_NUMBER, snap_id, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME, 
        PARSING_SCHEMA_NAME, 
        sql_id, PLAN_HASH_VALUE,
        executions_total,
        OPTIMIZER_COST,
        (ELAPSED_TIME_TOTAL/1e6)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL)/
        decode(PX_SERVERS_EXECS_TOTAL,0,1,PX_SERVERS_EXECS_TOTAL)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_etime,
        decode(PX_SERVERS_EXECS_TOTAL,0,1,PX_SERVERS_EXECS_TOTAL)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_px,
        BUFFER_GETS_TOTAL/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_lio,            
        VERSION_COUNT nochild_cursors,
        c.sql_text, aa.name command_type_desc,
        SQL_PROFILE,        
        decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,'No','Yes') Offload,
        decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,0,100*(IO_OFFLOAD_ELIG_BYTES_TOTAL-IO_INTERCONNECT_BYTES_TOTAL))
        /decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,1,IO_OFFLOAD_ELIG_BYTES_TOTAL) "IO_SAVED_%"            
from DBA_HIST_SQLSTAT a  left outer join
     DBA_HIST_SNAPSHOT b using (SNAP_ID) left outer join
     DBA_HIST_SQLTEXT c using (SQL_ID) left outer join
     audit_actions aa on (COMMAND_TYPE = aa.ACTION)      
where
    upper(dbms_lob.substr(sql_text, 4000, 1)) like upper(nvl('&sql_text',upper(dbms_lob.substr(sql_text, 4000, 1))))  --use dbms_lob.substr in order not to get an "ORA-22835: Buffer too small for CLOB to CHAR or BLOB to RAW conversion"
    and sql_id  --= nvl(trim('&sql_id'),sql_id)
        in (
                select sql_id
                from (
                select t.*,  case when upper(sql.sql_text) like '%USAGE_FCT%' then 1 else 0  END USAGE_FCT_FLAG, case when upper(sql.sql_text) like '%ICT_USAGE_FCT%' then 1 else 0  END ICT_USAGE_FCT_FLAG, sql.sql_text 
                from (
                select trunc(sample_time) stime, sql_id, count(*), round(sum(10)/60) mins, rank() over(partition by trunc(sample_time) order by round(sum(10)/60) desc) rank --sample_time,trunc(sample_time), (sample_time - trunc(sample_time)),interval '16' hour , interval '24' hour   --* 
                from dba_hist_active_sess_history
                where
                module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
                AND sample_time between to_date('2014-03-26','yyyy-mm-dd') and to_date('2014-04-17', 'yyyy-mm-dd') -- problem period
                AND (sample_time - trunc(sample_time)) between interval '16' hour and interval '24' hour -- only within the maintenance window 16:00 to 00:00 
                and user_id = 0 -- sys
                group by trunc(sample_time),sql_id 
                --order by 1, count(*) desc
                ) t, dba_hist_sqltext sql
                where 
                t.sql_id = sql.sql_id
                and t.mins > 60
                and t.sql_id is not NULL
                and rank < 6
                order by stime, rank
                )
                group by sql_id
                        
        )
)
group by --trunc(BEGIN_INTERVAL_TIME),
sql_id
having count(distinct plan_hash_value) > 1
order by 1    

--bt0vcngwaw6zd    2

-- find when change of execution plan took place  for bt0vcngwaw6zd
select trunc(BEGIN_INTERVAL_TIME), 
plan_hash_value, count(*)
from (
select    a.INSTANCE_NUMBER, snap_id, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME, 
        PARSING_SCHEMA_NAME, 
        sql_id, PLAN_HASH_VALUE,
        executions_total,
        OPTIMIZER_COST,
        (ELAPSED_TIME_TOTAL/1e6)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL)/
        decode(PX_SERVERS_EXECS_TOTAL,0,1,PX_SERVERS_EXECS_TOTAL)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_etime,
        decode(PX_SERVERS_EXECS_TOTAL,0,1,PX_SERVERS_EXECS_TOTAL)/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_px,
        BUFFER_GETS_TOTAL/decode(nvl(EXECUTIONS_TOTAL,0),0,1,EXECUTIONS_TOTAL) avg_lio,            
        VERSION_COUNT nochild_cursors,
        c.sql_text, aa.name command_type_desc,
        SQL_PROFILE,        
        decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,'No','Yes') Offload,
        decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,0,100*(IO_OFFLOAD_ELIG_BYTES_TOTAL-IO_INTERCONNECT_BYTES_TOTAL))
        /decode(IO_OFFLOAD_ELIG_BYTES_TOTAL,0,1,IO_OFFLOAD_ELIG_BYTES_TOTAL) "IO_SAVED_%"            
from DBA_HIST_SQLSTAT a  left outer join
     DBA_HIST_SNAPSHOT b using (SNAP_ID) left outer join
     DBA_HIST_SQLTEXT c using (SQL_ID) left outer join
     audit_actions aa on (COMMAND_TYPE = aa.ACTION)      
where
    upper(dbms_lob.substr(sql_text, 4000, 1)) like upper(nvl('&sql_text',upper(dbms_lob.substr(sql_text, 4000, 1))))  --use dbms_lob.substr in order not to get an "ORA-22835: Buffer too small for CLOB to CHAR or BLOB to RAW conversion"
    and sql_id = nvl(trim('&sql_id'),sql_id)
)
group by trunc(BEGIN_INTERVAL_TIME),
 plan_hash_value
order by 1    

/*
TRUNC(BEGIN_INTERVAL_TIME)    PLAN_HASH_VALUE    COUNT(*)
08-03-2014    3645025857    12
09-03-2014    3645025857    8
10-03-2014    3645025857    16
13-03-2014    3645025857    4
14-03-2014    3645025857    4
15-03-2014    2715593868    4
15-03-2014    3645025857    8
16-03-2014    2715593868    8
16-03-2014    3645025857    24
17-03-2014    3645025857    8
17-03-2014    2715593868    4
18-03-2014    3645025857    12
19-03-2014    3645025857    12
20-03-2014    3645025857    12
20-03-2014    2715593868    4
21-03-2014    3645025857    12
21-03-2014    2715593868    4
22-03-2014    3645025857    16
23-03-2014    3645025857    8
23-03-2014    2715593868    8
24-03-2014    2715593868    4
24-03-2014    3645025857    16
25-03-2014    3645025857    8
26-03-2014    3645025857    4
29-03-2014    3645025857    8
30-03-2014    3645025857    8
31-03-2014    2715593868    4
31-03-2014    3645025857    24
01-04-2014    2715593868    4
01-04-2014    3645025857    20
02-04-2014    3645025857    12
03-04-2014    3645025857    20
04-04-2014    3645025857    12
05-04-2014    2715593868    16
05-04-2014    3645025857    24
06-04-2014    3645025857    28
06-04-2014    2715593868    16
07-04-2014    3645025857    4
08-04-2014    3645025857    4
09-04-2014    3645025857    4
10-04-2014    3645025857    8
11-04-2014    3645025857    12
12-04-2014    3645025857    4
13-04-2014    2715593868    4
13-04-2014    3645025857    4
14-04-2014    3645025857    12
15-04-2014    3645025857    24
16-04-2014    3645025857    28
*/

-- find segments last analyzed for a specific day

from dba_tab_subpartitions
where table_name = 'USAGE_FCT'
and table_owner = 'TARGET_DW'


select trunc(last_analyzed),count(distinct subpartition_name)
from dba_tab_subpartitions
where table_name = 'USAGE_FCT'
and table_owner = 'TARGET_DW'
and trunc(last_analyzed) between date'2014-05-10' and date'2014-05-11'
group by trunc(last_analyzed)


select count(*)
from dba_tab_partitions
where table_name = 'USAGE_FCT'
and table_owner = 'TARGET_DW'
and trunc(last_analyzed) = date'2014-05-11'

select max(last_analyzed)
from dba_tables
where table_name = 'USAGE_FCT'
and owner = 'TARGET_DW'

-- indexes
select trunc(last_analyzed),count(*)
from dba_ind_subpartitions
where
(index_owner,index_name) in (select index_owner,index_name from dba_indexes where table_name = 'USAGE_FCT' and table_owner = 'TARGET_DW')
and trunc(last_analyzed) between date'2014-05-13' and date'2014-05-14'
group by trunc(last_analyzed)

select count(*)
from dba_ind_partitions
where
(index_owner,index_name) in (select index_owner,index_name from dba_indexes where table_name = 'USAGE_FCT' and table_owner = 'TARGET_DW')
and trunc(last_analyzed) = date'2014-05-11'



select max(last_analyzed)
from dba_tab_subpartitions
where table_name = 'ICT_USAGE_FCT'
and table_owner = 'ICT_DW'

select count(*)
from dba_tab_subpartitions
where table_name = 'ICT_USAGE_FCT'
and table_owner = 'ICT_DW'
and trunc(last_analyzed) = date'2014-05-19'


select max(last_analyzed)
from dba_tab_partitions
where table_name = 'ICT_USAGE_FCT'
and table_owner = 'ICT_DW'

select count(*)
from dba_tab_partitions
where table_name = 'ICT_USAGE_FCT'
and table_owner = 'ICT_DW'
and trunc(last_analyzed) = date'2014-05-19'

select last_analyzed
from dba_tables
where table_name = 'ICT_USAGE_FCT'
and owner = 'ICT_DW'

-- indexes
select index_name, last_analyzed
from dba_indexes
where 
table_name = 'ICT_USAGE_FCT' and table_owner = 'ICT_DW'

select count(*)
from dba_ind_subpartitions
where
(index_owner,index_name) in (select index_owner,index_name from dba_indexes where table_name = 'ICT_USAGE_FCT' and table_owner = 'ICT_DW')
and trunc(last_analyzed) = date'2014-05-19'

select count(*)
from dba_ind_partitions
where
(index_owner,index_name) in (select index_owner,index_name from dba_indexes where table_name = 'ICT_USAGE_FCT' and table_owner = 'ICT_DW')
and trunc(last_analyzed) = date'2014-05-19'



------------------------------ DRAFT


select 8*60
from dual

select *
from (
select sql_id, count(*) cnt
from dba_hist_active_sess_history t
where
module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
AND sample_time between to_date('2014-04-16 18:35:00','yyyy-mm-dd hh24:mi:ss') and to_date('2014-04-16 18:45:00','yyyy-mm-dd hh24:mi:ss') -- problem period
--AND (sample_time - trunc(sample_time)) between interval '16' hour and interval '24' hour -- only within the maintenance window 16:00 to 00:00 
and user_id = 0 -- sys
group by t.sql_id) t, dba_hist_sqltext sql
where
t.sql_id = sql.sql_id
order by cnt desc

select *
from (
    select t.* 
    from (
    select trunc(sample_time) stime, sql_id, count(*) cnt, round(sum(10)/60) mins, rank() over(partition by trunc(sample_time) order by round(sum(10)/60) desc) rank --sample_time,trunc(sample_time), (sample_time - trunc(sample_time)),interval '16' hour , interval '24' hour   --* 
    from dba_hist_active_sess_history
    where
    module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
    AND sample_time between to_date('2014-03-26','yyyy-mm-dd') and to_date('2014-04-17', 'yyyy-mm-dd') -- problem period
    AND (sample_time - trunc(sample_time)) between interval '16' hour and interval '24' hour -- only within the maintenance window 16:00 to 00:00 
    and user_id = 0 -- sys
    group by trunc(sample_time),sql_id 
    --order by 1, count(*) desc
    ) t
    where 
    t.mins > 60
    and t.sql_id is not NULL
    and rank < 3
    order by stime, rank
) tt
PIVOT (
    sum(tt.cnt) FOR STIME in (
date'2014-03-26',
date'2014-03-27',
date'2014-03-28',
date'2014-03-29',
date'2014-03-30',
date'2014-03-31',
date'2014-04-01',
date'2014-04-02',
date'2014-04-03',
date'2014-04-04',
date'2014-04-05',
date'2014-04-06',
date'2014-04-07',
date'2014-04-08',
date'2014-04-09',
date'2014-04-10',
date'2014-04-11',
date'2014-04-12',
date'2014-04-13',
date'2014-04-14',
date'2014-04-15',
date'2014-04-16'                     
                          ))
order by rank                                 


select 'date'||''''|| to_char(to_date('2014-03-25','yyyy-mm-dd') + rownum, 'YYYY-MM-DD')||''''||','  
                            from dba_tables 
                            where rownum < (to_date('2014-04-17', 'yyyy-mm-dd') - to_date('2014-03-26','yyyy-mm-dd')+1) 


select *
from dba_hist_sqltext
where sql_id = '9q7k9nbpvk8pv'

select 1417/60 from dual

select (sysdate - trunc(sysdate))*24 
from dual
where 
(sysdate - trunc(sysdate))*24 between 16 and 24


select 1490/60 from dual