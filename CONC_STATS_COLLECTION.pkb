CREATE OR REPLACE PACKAGE BODY DWADMIN.CONC_STATS_COLLECTION AS

PROCEDURE MAIN(ownname_in in varchar2, tabname_in in varchar2) IS
    l_start date; 
    l_minutes_waiting integer;   
BEGIN
    -- Check conditions in order to run stats collection
    
    -- if it is the 1st of the month, then exit
        if(to_char(sysdate, 'DD') = '01') then
            return;
        end if;
        
        -- if current time > time_threshold then exit
        if( numtodsinterval((sysdate - trunc(sysdate))*24,'HOUR') > g_time_threshold ) then
            return;
        end if;             
                          
        l_minutes_waiting := 0;
    -- if NMR has NOT finished yet OR CTO has not finished, then wait ...
        WHILE (DWADMIN.CONC_STATS_COLLECTION.NMR_HAS_FINISHED = 0  OR DWADMIN.CONC_STATS_COLLECTION.CTO_HAS_FINISHED = 0 ) LOOP
            -- DEBUGGING code
            --dbms_output.put_line('sleeping for '||g_sleep_minutes);
            
           -- sleep for 10 minutes
           dbms_lock.sleep(g_sleep_minutes*60);
           
           l_minutes_waiting := l_minutes_waiting  + g_sleep_minutes;
           
           -- if waiting for more than threshold then forget it.
           if(l_minutes_waiting  > g_mins_waiting_threshold) then
                return;
           end if;                
                                
        END LOOP;
        
        -- if current time <= time_threshold then run
        if( numtodsinterval((sysdate - trunc(sysdate))*24,'HOUR') <= g_time_threshold ) then
            -- collect stats
            if((upper(ownname_in) = 'ICT_DW' AND upper(tabname_in) = 'ICT_USAGE_FCT' ) OR (upper(ownname_in) = 'TARGET_DW' AND upper(tabname_in) = 'USAGE_FCT' )) then
                -- log a message
                l_start := sysdate;
                LOG_CONC_STATS_COLLECTION(startdt_in=>l_start, message_in=>'STARTING Stats Collection for '||ownname_in||'.'||tabname_in);
                BEGIN
                    -- **** NOTE ****
                    -- after experimenting, we found out that we nned to reduce this parameter
                    -- in order to avoid error:ERROR in Stats Collection for TARGET_DW.USAGE_FCT: -20001:ORA-20001: ORA-04021: timeout occurred while waiting to lock object
                    -- ************** 
                    execute immediate 'ALTER SYSTEM SET job_queue_processes = 15 SID = ''*'''; 
                    
                    dbms_stats.gather_table_stats(ownname=>ownname_in, tabname=>tabname_in, estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE, cascade=>DBMS_STATS.AUTO_CASCADE, degree=>NULL);
                    
                    execute immediate 'ALTER SYSTEM SET job_queue_processes = 70 SID = ''*''';
                    -- DEBUGGING code
                    --dbms_output.put_line(ownname_in||'.'||tabname_in);
                EXCEPTION
                    WHEN OTHERS THEN
                        LOG_CONC_STATS_COLLECTION(startdt_in=>l_start, enddt_in=>sysdate, operation_in=>'UPDATE', 
                            message_in=>'ERROR in Stats Collection for '||ownname_in||'.'||tabname_in||': '||SQLCODE||':'||SQLERRM);
                        raise;                                                                        
                END;
                -- log a message
                LOG_CONC_STATS_COLLECTION(startdt_in=>l_start, enddt_in=>sysdate, operation_in=>'UPDATE', message_in=>'ENDING Stats Collection for '||ownname_in||'.'||tabname_in);            
            else
                raise_application_error(-20001, 'Unknown table name or table owner.Only ICT_DW.ICT_USAGE_FCT and TARGET_DW.USAGE_FCT are currently supported.');
            end if;            
        end if;             
        
        return;
END main;

FUNCTION NMR_HAS_FINISHED RETURN INTEGER IS
l_result    varchar(50);
BEGIN
    with kpi as
    (
    SELECT RUN_DATE        
        FROM STAGE_DW.DW_CONTROL_TABLE        
        WHERE PROCEDURE_NAME = 'NMR_GLOBAL_RUN_DATE'
    ),
    kpi_run as (
    SELECT RUN_DATE        
        FROM STAGE_DW.DW_CONTROL_TABLE        
        WHERE PROCEDURE_NAME = 'NMR_GLOBAL_END_DATE'
    )
    SELECT 
        case when
            (select trunc(run_date) from kpi_run) =  trunc(sysdate) -- NMR has been executed at least once within the day
        AND 
            (select trunc(run_date) from kpi) >= trunc(sysdate) -- NMR is in no need of catchup 
        then    'NMR has been completed'    ELSE    'currently executing or waiting to execute'
        end KPIDW_MAIN  into l_result                                   
    from dual;

    IF(l_result = 'NMR has been completed') THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
                    
END NMR_HAS_FINISHED;

FUNCTION CTO_HAS_FINISHED RETURN INTEGER IS
l_result    varchar(50);
BEGIN
    with cto as
    (
    SELECT RUN_DATE        
        FROM STAGE_DW.DW_CONTROL_TABLE        
        WHERE PROCEDURE_NAME = 'CTO_LAST_RUN'
    ),
    cto_run as (
    SELECT RUN_DATE        
        FROM STAGE_DW.DW_CONTROL_TABLE        
        WHERE PROCEDURE_NAME = 'CTO_END_DATE'
    )
    SELECT 
        case when
            (select trunc(run_date) from cto_run) =  trunc(sysdate) -- CTO has been executed at least once within the day
        AND 
            (select trunc(run_date)+1 from cto) >= trunc(sysdate) -- CTO is in no need of catchup 
        then    'CTO has been completed'    ELSE    'currently executing or waiting to execute'
        end CTO_MAIN  into l_result                                   
    from dual;

    IF(l_result = 'CTO has been completed') THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
                    
END CTO_HAS_FINISHED;

PROCEDURE LOG_CONC_STATS_COLLECTION (startdt_in in date, enddt_in in date, operation_in varchar2, message_in varchar2)
IS
BEGIN
    if(operation_in = 'INSERT') then
        insert into dwadmin.conc_stats_collection_log (start_date, end_date, message) 
            values (startdt_in, enddt_in, message_in); 
        commit;                      
    elsif (operation_in = 'UPDATE') then
        update dwadmin.conc_stats_collection_log 
            set end_date = enddt_in,
                message = message_in
        where
            start_date = startdt_in;
            
        commit;                            
    else
        raise_application_error(-20001, 'Unknown operation in procedure CONC_STATS_COLLECTION.LOG_CONC_STATS_COLLECTION');
    end if;

    return;
END LOG_CONC_STATS_COLLECTION;

    
END CONC_STATS_COLLECTION;