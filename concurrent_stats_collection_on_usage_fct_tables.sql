/*
Goal -->
 Gather stats on ICT_USAGE_FCT and USAGE_FCT  with CONCURRENT preferenc set to true and see how it goes
*/

/*****************************************************************

 How to monitor and control the job

******************************************************************/

-- Get job info. Check status! 
select  OWNER, JOB_NAME, JOB_SUBNAME, ENABLED, STATE, START_DATE,LAST_START_DATE, NEXT_RUN_DATE,  repeat_interval,RUN_COUNT, MAX_RUN_DURATION
from dba_scheduler_jobs
where
owner = 'DWADMIN'
and    job_name like '%CHAIN'

-- how many jobs are ccurently running
select * -- owner, job_name, comments current_segment
from dba_scheduler_jobs
where
 owner = 'DWADMIN' and 
 job_name like 'ST%'
 and state = 'RUNNING' 
    -- no rows


    --Posa exoun programmatistei
SELECT job_name, state, comments
FROM dba_scheduler_jobs
WHERE job_class LIKE 'CONC%'
AND state = 'SCHEDULED';


--Posa trexoun
SELECT job_name, state, comments
FROM dba_scheduler_jobs
WHERE job_class LIKE 'CONC%'
AND state = 'RUNNING';


-- check running jobs
select *
from DBA_SCHEDULER_RUNNING_JOBS
    

-- watch ACTIVE session as they are generated   
select nvl(to_char(logon_time, 'dd-mm-yyyy hh24:mi'), 'TOTAL') logon, count(*)
from gv$session 
where username = 'DWADMIN'
      and status = 'ACTIVE'
group by rollup (to_char(logon_time, 'dd-mm-yyyy hh24:mi'))    
order by 1 desc 

select wait_class, event, round(WAIT_TIME_MICRO/1e6/60,1) tot_waiting_mins, count(*) over(partition by wait_class, event) how_many_on_this_event
from gv$session
where username = 'DWADMIN'
and state = 'WAITING'
order by 3 desc


select wait_class, event, count(*)
from gv$session
where username = 'DWADMIN'
and state = 'WAITING'
group by wait_class, event
order by 3 desc

    
-- Get job duration for succeded jobs
select owner, job_name, job_subname, status, actual_start_date, run_duration
from ALL_SCHEDULER_JOB_RUN_DETAILS
where
 owner = 'DWADMIN' and job_name like '%CHAIN'
 and status = 'SUCCEEDED' 
order by actual_start_date desc

-- Check  my log table
 select (end_date-start_date)*24*60 duration_mins, t.*
 from dwadmin.conc_stats_collection_log t
 order by start_date desc
 
-- Check  my log table (succeeded jobs only!) 
 select (end_date-start_date)*24*60 duration_mins, t.*
 from dwadmin.conc_stats_collection_log t
 where 
    message in ('ENDING Stats Collection for TARGET_DW.USAGE_FCT', 'ENDING Stats Collection for ICT_DW.ICT_USAGE_FCT')
 order by start_date desc 
 
-- check log of job executions
select *
from DBA_SCHEDULER_JOB_LOG
where 1=1 
and owner = 'DWADMIN'
and    job_name like '%CHAIN'
order by log_date desc

-- check execution details
select *
from DBA_SCHEDULER_JOB_RUN_DETAILS
where 1=1 
and owner = 'DWADMIN'
and    job_name like '%CHAIN'
order by log_date desc
 
 
 -- stop the job when running
begin
  dbms_scheduler.stop_job(job_name => 'DWADMIN.CONC_STATS_USAGE_FROM_CHAIN',
  force => TRUE);
end;
/ 

-- disable job
BEGIN
sys.dbms_scheduler.disable( '"DWADMIN"."CONC_STATS_USAGE_FROM_CHAIN"' ); 
END

--run job now
begin
  dbms_scheduler.run_job('"DWADMIN"."CONC_STATS_USAGE_FROM_CHAIN"',TRUE);
end;
/



-- check duration of concurrent stats execution job after successful completion    
select owner, job_name, status, actual_start_date, run_duration
from ALL_SCHEDULER_JOB_RUN_DETAILS
where
 owner = 'DWADMIN' and job_name like 'ST%'
 and status = 'SUCCEEDED' 
order by actual_start_date desc 

-- how many concurrent jobs are allowed in the system(per node)
nkarag@DWHPRD> show parameter job_q

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------
job_queue_processes                  integer     60

       
select *
from dba_scheduler_running_jobs    

-- check log of job executions
select *
from DBA_SCHEDULER_JOB_LOG
where 1=1 
and owner = 'DWADMIN'
and    job_name like '%CHAIN'
order by log_date desc

-- check execution details
select *
from DBA_SCHEDULER_JOB_RUN_DETAILS
where 1=1 
and owner = 'DWADMIN'
and    job_name like '%CHAIN'
order by log_date desc

/**********************************************************************************
    Troublshooting 2016-05-16
    
    Find what is blocking the statistics gathering and return error:
    
    "ERROR in Stats Collection for TARGET_DW.USAGE_FCT: -20001:ORA-20001: ORA-04021: timeout occurred while waiting to lock object 
ORA-06512: at "SYS.DBMS_STATS", line 23862
ORA-06512: at "SYS.DBMS_STATS", line 23931
ORA-06512: at line 1"

***********************************************************************************/ 

-- find the blocker from ASH history
select  (select distinct user_id from dba_hist_active_sess_history where session_id = t.blocking_session and instance_number = t.blocking_inst_id and blocking_session_serial# = session_serial#) user_id,
        t.*
from dba_hist_active_sess_history t
where 
    user_id = (select user_id from dba_users where username = 'DWADMIN')
    and sample_time between to_date('08-05-2016', 'dd-mm-yyyy') and to_date('09-05-2016', 'dd-mm-yyyy')   --sample_time between to_date('08-05-2016 15:20:47', 'dd-mm-yyyy hh24:mi:ss') AND to_date('08-05-2016 15:30:47', 'dd-mm-yyyy hh24:mi:ss')
    and BLOCKING_SESSION is not null
    and  plsql_object_id = 8032 -- dbms_stats
    and plsql_subprogram_id = 133 -- gather_table_Stats
order by sample_time     
    
    
-- dbms_stats.gather_table_stats    
select *
from dba_procedures
where
    object_id = 8032   and subprogram_id = 76
    
/**********************************************************************************
    
    Implementation

***********************************************************************************/ 
    

    
 
-- how many jobs will run within this morning
select owner, job_name, job_creator, NEXT_RUN_DATE
from dba_scheduler_jobs
where
    enabled = 'TRUE'
    and NEXT_RUN_DATE between sysdate and trunc(sysdate + 1)
order by NEXT_RUN_DATE
  
/*
OWNER                          JOB_NAME                  JOB_CREATOR                    NEXT_RUN_DATE
------------------------------ ------------------------- ------------------------------ --------------------------------------------
MONITOR_DW                     EMAIL_MECHANISM           EFOTOPOULOS                    19-MAY-14 09.45.00.000000 AM EUROPE/ATHENS
APEX_040100                    ORACLE_APEX_MAIL_QUEUE    SYS                            19-MAY-14 09.45.00.100000 AM +03:00
DWADMIN                        ENABLE_VPN_TRIGGER        DWADMIN                        19-MAY-14 10.00.00.100000 AM EUROPE/ATHENS
APEX_040100                    ORACLE_APEX_WS_NOTIFICATI SYS                            19-MAY-14 10.00.00.500000 AM +03:00
APEX_040100                    ORACLE_APEX_PURGE_SESSION SYS                            19-MAY-14 10.00.44.000000 AM +03:00
REPORT_DW                      CR1609_PROC_MON_JOB       PKIOUSIS                       19-MAY-14 11.00.00.700000 AM EUROPE/ATHENS
REPORT_DW                      CR2056A_DP_EC_APER_MJ     EFOTOPOULOS                    19-MAY-14 11.10.00.800000 AM +03:00
REPORT_DW                      CR1611_OTEDP3050_APERPLUS EFOTOPOULOS                    19-MAY-14 01.00.00.400000 PM +03:00
REPORT_DW                      CR1739_VDSL_30_50_PKG_MJ  EFOTOPOULOS                    19-MAY-14 01.00.00.600000 PM +03:00
REPORT_DW                      CR1716_OTE_MOBILE_PKG_MJ  EFOTOPOULOS                    19-MAY-14 01.00.00.600000 PM +03:00
REPORT_DW                      CR1610_OTEDP3050_APER_MJ  EFOTOPOULOS                    19-MAY-14 01.00.00.800000 PM +03:00
MONITOR_DW                     DWMON_LOG_FRESH_OF_DATA_J MONITOR_DW                     19-MAY-14 01.00.00.800000 PM +03:00
REPORT_DW                      CR1759_PROC_MON_JOB       LSINOS                         19-MAY-14 01.00.00.900000 PM +03:00
MONITOR_DW                     DWMON_START_MONITOR_INDEX MONITOR_DW                     19-MAY-14 04.00.00.000000 PM EUROPE/ATHENS
MONITOR_DW                     GET_SQL_HIST              MONITOR_DW                     19-MAY-14 08.00.00.300000 PM EUROPE/ISTANBUL
MONITOR_DW                     DWH_PWD_NOTIFICATION      MONITOR_DW                     19-MAY-14 08.00.00.800000 PM EUROPE/ATHENS
*/


-- give privileges for concurrent stats collection to users
grant CREATE JOB to ETL_DW;
 
grant MANAGE SCHEDULER to ETL_DW;
 
grant MANAGE ANY QUEUE to ETL_DW; 

grant CREATE JOB to PERIF;
 
grant MANAGE SCHEDULER to PERIF;
 
grant MANAGE ANY QUEUE to PERIF;

grant CREATE JOB to DWADMIN;
 
grant MANAGE SCHEDULER to DWADMIN;
 
grant MANAGE ANY QUEUE to DWADMIN;

grant CREATE JOB to DM_SAS;
 
grant MANAGE SCHEDULER to DM_SAS;
 
grant MANAGE ANY QUEUE to DM_SAS; 

grant CREATE JOB to NKARAG;
 
grant MANAGE SCHEDULER to NKARAG;
 
grant MANAGE ANY QUEUE to NKARAG;

grant CREATE JOB to LSINOS;
 
grant MANAGE SCHEDULER to LSINOS;
 
grant MANAGE ANY QUEUE to LSINOS; 
 
grant CREATE JOB to ITHEODORAKIS;
 
grant MANAGE SCHEDULER to ITHEODORAKIS;
 
grant MANAGE ANY QUEUE to ITHEODORAKIS; 

grant CREATE JOB to IMAYRAKAKIS;
 
grant MANAGE SCHEDULER to IMAYRAKAKIS;
 
grant MANAGE ANY QUEUE to IMAYRAKAKIS;

grant CREATE JOB to GPAPOUTSOPOULOS;
 
grant MANAGE SCHEDULER to GPAPOUTSOPOULOS;
 
grant MANAGE ANY QUEUE to GPAPOUTSOPOULOS; 

grant CREATE JOB to LALEXIOU;
 
grant MANAGE SCHEDULER to LALEXIOU;
 
grant MANAGE ANY QUEUE to LALEXIOU;

grant CREATE JOB to DPSYCHOGIOPOULOS;
 
grant MANAGE SCHEDULER to DPSYCHOGIOPOULOS;
 
grant MANAGE ANY QUEUE to DPSYCHOGIOPOULOS;

grant CREATE JOB to AMANTES;
 
grant MANAGE SCHEDULER to AMANTES;
 
grant MANAGE ANY QUEUE to AMANTES;



-- set conccurent preference on
select dbms_stats.get_prefs('CONCURRENT', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- FALSE

select dbms_stats.get_prefs('CONCURRENT', 'TARGET_DW', 'USAGE_FCT') from dual;
--FALSE

dwadmin@DWHPRD> BEGIN
  2  DBMS_STATS.SET_GLOBAL_PREFS('CONCURRENT','TRUE');
  3  END;
  4  /
--PL/SQL procedure successfully completed.

select dbms_stats.get_prefs('CONCURRENT', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- TRUE

select dbms_stats.get_prefs('CONCURRENT', 'TARGET_DW', 'USAGE_FCT') from dual;
--TRUE


-- create job to gather the stats concurrently
-- fist check default values of gather_table_stats input parameters
select dbms_stats.get_prefs('ESTIMATE_PERCENT', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- DBMS_STATS.AUTO_SAMPLE_SIZE

select dbms_stats.get_prefs('ESTIMATE_PERCENT', 'TARGET_DW', 'USAGE_FCT') from dual;
-- DBMS_STATS.AUTO_SAMPLE_SIZE

select dbms_stats.get_prefs('CASCADE', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- FALSE

select dbms_stats.get_prefs('CASCADE', 'TARGET_DW', 'USAGE_FCT') from dual;
-- FALSE

select dbms_stats.get_prefs('DEGREE', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- 64

select dbms_stats.get_prefs('DEGREE', 'TARGET_DW', 'USAGE_FCT') from dual;
-- 64

select dbms_stats.get_prefs('GRANULARITY', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- AUTO

select dbms_stats.get_prefs('GRANULARITY', 'TARGET_DW', 'USAGE_FCT') from dual;
-- AUTO


select dbms_stats.get_prefs('INCREMENTAL', 'ICT_DW', 'ICT_USAGE_FCT') from dual;
-- TRUE

select dbms_stats.get_prefs('INCREMENTAL', 'TARGET_DW', 'USAGE_FCT') from dual;
-- TRUE

-- ***************** gather_table_stats  statement ICT_USAGE_FCT
begin
    dbms_stats.gather_table_stats(ownname=>'ICT_DW', tabname=>'ICT_USAGE_FCT', estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE, cascade=>DBMS_STATS.AUTO_CASCADE, degree=>NULL);
end;
--******************

-- ***************** gather_table_stats  statement USAGE_FCT
begin
    dbms_stats.gather_table_stats(ownname=>'TARGET_DW', tabname=>'USAGE_FCT', estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE, cascade=>DBMS_STATS.AUTO_CASCADE, degree=>NULL);
end;
--******************


-- create job SQL
BEGIN
sys.dbms_scheduler.create_job( 
job_name => '"DWADMIN"."STATS_CONC_ICT_USAGE_FCT"',
job_type => 'PLSQL_BLOCK',
job_action => 'begin
dbms_stats.gather_table_stats(owner=>''ICT_DW'', tabname=>''ICT_USAGE_FCT'', cascade=>DBMS_STATS.AUTO_CASCADE, degree=>NULL);
end;',
start_date => systimestamp at time zone 'Europe/Athens',
job_class => '"DEFAULT_JOB_CLASS"',
comments => 'gather table stats on ICT_DW.ICT_USAGE_FCT concurrenlty',
auto_drop => FALSE,
enabled => TRUE);
END;

/*******************************************************************************

    Conditions in order for the concurrent statistics gathering must take place:
    
        - Dont run if NMR has not finished
        - Dont run if it is the 1st of the month
        - Dont run if it is after 17:00
        - Create a job chain: first the usage_fct must be completed and then the ICT_USAGE can start

-- create package DWADMIN.CONC_STATS_COLLECTION

********************************************************************************/

BEGIN
    -- Check conditions in order to run
    
    -- if it is the 1st of the month, then exit
    
    -- if sysdate > 17:00 then exit
    
    -- if NMR has finished the run
        
    -- else 
        -- loop
            -- sleep for 10 minutes
        -- loop WHILE (NMR has NOT finished)
        
        -- if sysdate <= 17:00 then run  
        
END;

select DWADMIN.CONC_STATS_COLLECTION.NMR_HAS_FINISHED from dual;


-- create a table to log concurrent statistics collection
create table dwadmin.conc_stats_collection_log (
    start_date  date,
    end_date    date,
    message     varchar2(4000)
);


-- call the package like this:
begin
    DWADMIN.CONC_STATS_COLLECTION.main('ICT_DW', 'ICT_USAGE_FCT');
    
    DWADMIN.CONC_STATS_COLLECTION.main('TARGET_DW', 'USAGE_FCT');
end;

/*****************************************************************

 Create two Programs (one for each call to DWADMIN.CONC_STATS_COLLECTION.main)

******************************************************************/

begin
    
    DBMS_SCHEDULER.CREATE_PROGRAM(
    program_name=>'"DWADMIN"."CONC_STATS_USAGE_FCT_PROG"',
    program_action=>'DWADMIN.CONC_STATS_COLLECTION.main(''TARGET_DW'', ''USAGE_FCT'');',
    program_type=>'PLSQL_BLOCK',
    number_of_arguments=>0,
    comments=>'Gather stats concurrently for TARGET_DW.USAGE_FCT',
    enabled=>FALSE);
        
    dbms_scheduler.create_program(
         program_name => '"DWADMIN"."CONC_STATS_ICT_USAGE_FCT_PROG"',
         program_type => 'PLSQL_BLOCK',
         program_action => 'DWADMIN.CONC_STATS_COLLECTION.main(''ICT_DW'', ''ICT_USAGE_FCT'');',
         number_of_arguments => 0,
         comments => 'Gather stats concurrently for ICT_DW.ICT_USAGE_FCT',
         enabled=>FALSE 
    );
    
end;

/*****************************************************************

 Create a Chain:
    First the USAGE_FCT stats collection starts
    and if this is finished on SUCCESS then the ICT_USAGE_FCT program starts
    

 Then Create a Job to run this chain    

******************************************************************/

grant CREATE ANY JOB to nkarag
grant CREATE ANY JOB to dwadmin

grant CREATE ANY RULE SET to nkarag
grant CREATE ANY RULE SET to dwadmin

grant CREATE ANY EVALUATION CONTEXT to nkarag
grant CREATE ANY EVALUATION CONTEXT to dwadmin

grant DROP ANY RULE SET to nkarag
grant DROP ANY RULE SET to dwadmin

grant DROP ANY EVALUATION CONTEXT to nkarag
grant DROP ANY EVALUATION CONTEXT to dwadmin

-- Run the following as DWADMIN

-- drop the CHAIN if already exists
BEGIN
   DBMS_SCHEDULER.DROP_CHAIN (
   chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
   force => TRUE);
END;


BEGIN
sys.dbms_scheduler.create_chain( 
comments => 'Collect stats concurrenty first on USAGE_FCT and then (on success) on ICT_USAGE_FCT.',
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"');
sys.dbms_scheduler.define_chain_step( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_USAGE_FCT"',
program_name => '"DWADMIN"."CONC_STATS_USAGE_FCT_PROG"');
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_USAGE_FCT"',
attribute => 'pause',
value => FALSE);
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_USAGE_FCT"',
attribute => 'skip',
value => FALSE);
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_USAGE_FCT"',
attribute => 'restart_on_failure',
value => FALSE);
sys.dbms_scheduler.define_chain_step( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_ICT_USG_FCT"',
program_name => '"DWADMIN"."CONC_STATS_ICT_USAGE_FCT_PROG"');
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_ICT_USG_FCT"',
attribute => 'pause',
value => FALSE);
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_ICT_USG_FCT"',
attribute => 'skip',
value => FALSE);
sys.dbms_scheduler.alter_chain( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
step_name => '"COLL_STATS_ICT_USG_FCT"',
attribute => 'restart_on_failure',
value => FALSE);
sys.dbms_scheduler.define_chain_rule( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
condition => 'TRUE',
rule_name => 'START_1ST_STEP_RULE',
comments => 'start usage_fct stats collection',
action => 'START COLL_STATS_USAGE_FCT');

--sys.dbms_scheduler.define_chain_rule( 
--chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
--condition => 'COLL_STATS_USAGE_FCT SUCCEEDED',
--rule_name => 'START_2ND_STEP_RULE',
--comments => 'start ict_usage_fct stats collection only on success of previous step',
--action => 'START COLL_STATS_ICT_USG_FCT');

-- ***** change 3/10/2014 (start on completion not only on success)
sys.dbms_scheduler.define_chain_rule(  
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"', 
condition => 'COLL_STATS_USAGE_FCT COMPLETED', 
rule_name => 'START_2ND_STEP_RULE', 
comments => 'start ict_usage_fct stats collection only on completion of previous step', 
action => 'START COLL_STATS_ICT_USG_FCT') 

sys.dbms_scheduler.define_chain_rule( 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
condition => 'COLL_STATS_ICT_USG_FCT COMPLETED',
rule_name => 'END_CHAIN_RULE',
comments => 'end the chain after 2nd step completed (either on success or error or stopped)',
action => 'END');
END;


BEGIN
sys.dbms_scheduler.create_job( 
job_name => '"DWADMIN"."CONC_STATS_USAGE_FROM_CHAIN"',
job_type => 'CHAIN',
job_action => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"',
repeat_interval => 'FREQ=WEEKLY;BYDAY=SUN;BYHOUR=11;BYMINUTE=0;BYSECOND=0',
start_date => systimestamp at time zone 'Europe/Athens',
job_class => '"DEFAULT_JOB_CLASS"',
auto_drop => FALSE,
enabled => FALSE);
END;


-- before run you must first enable the job, the programs and the chain

-- enable program
BEGIN
DBMS_SCHEDULER.ENABLE(
name=>'"DWADMIN"."CONC_STATS_ICT_USAGE_FCT_PROG"');
END;

-- enable program
BEGIN
DBMS_SCHEDULER.ENABLE(
name=>'"DWADMIN"."CONC_STATS_USAGE_FCT_PROG"');
END;

-- enable chain
BEGIN
sys.dbms_scheduler.enable('"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"'); 
END;


-- enable job
BEGIN 
sys.dbms_scheduler.enable( '"DWADMIN"."CONC_STATS_USAGE_FROM_CHAIN"' ); 
END;




/**********************

How to troublshoot when the STATE of the job is CHAIN_STALLED.

***********************/

-- check the  state of all steps in the chain
select *
from   DBA_SCHEDULER_RUNNING_CHAINS


-- check the chain rules.
select *
from dba_SCHEDULER_CHAIN_RULES

--  if one or more rules are incorrect, you can use the DEFINE_CHAIN_RULE procedure to replace them (using the same rule names), or to create new rules.
exec sys.dbms_scheduler.define_chain_rule( - 
chain_name => '"DWADMIN"."USAGE_CONC_STATS_COLL_CHAIN"', -
condition => 'COLL_STATS_USAGE_FCT COMPLETED', -
rule_name => 'START_2ND_STEP_RULE', -
comments => 'start ict_usage_fct stats collection only on completion of previous step', -
action => 'START COLL_STATS_ICT_USG_FCT') 

-- you can enable the chain to continue by altering the state of one of its steps with the ALTER_RUNNING_CHAIN procedure.
-- change the state of step COLL_STATS_USAGE_FCT to'SUCCEEDED' in order to start the next step
exec DBMS_SCHEDULER.ALTER_RUNNING_CHAIN ( -
   job_name => 'CONC_STATS_USAGE_FROM_CHAIN' , -
   step_name => '"COLL_STATS_USAGE_FCT"', -
   attribute => 'STATE', -
   value  =>  'SUCCEEDED');
 

