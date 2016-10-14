CREATE OR REPLACE PACKAGE DWADMIN.CONC_STATS_COLLECTION AS

/***********************************************************
 *               GLOBAL VARIABLES
 ************************************************************/

-- Time threshold over which the stats collection will not start
    --g_time_threshold INTERVAL HOUR (2) TO MINUTE (2) := interval '15:00' hour to minute;
g_time_threshold INTERVAL DAY (3) TO SECOND (1) := to_dsinterval('0 15:00:00');
--select to_dsinterval('0 15:00:00') from dual
g_sleep_minutes integer := 10;
-- threshold of how many minutes we are willing to wait for NMR to  finish.
g_mins_waiting_threshold integer := 300;  -- 5 hours waiting

/***********************************************************
 *               Procedures
 ************************************************************/

/*
    Main Function: Evaluates conditions in order to collect statistics for the input table
    Note: conditions are taylored for concurrent statistics gathering on the very large tables ICT_DW.ICT_USAGE_FCT and TARGET_DW.USAGE_FCT
        Also statistics gathering parameters are taylored to these tables as well.
    
    @parameters:
        ownname   input   Owner of the table
        tabname   input     Table name of the table for which statistics will be gathered.    
*/
PROCEDURE MAIN(ownname_in in varchar2, tabname_in in varchar2);

/*
 Retuns 1 if KPIDW_MAIN has finished execution, or 0 otherwise.
 A 1 means that:
    A. NMR has been executed within the day (at least once)
    B. NMR is up to date (no need for catch up)
*/
FUNCTION NMR_HAS_FINISHED RETURN INTEGER;

/*
 Retuns 1 if CTO_MAIN has finished execution, or 0 otherwise.
 A 1 means that:
    A. CTO has been executed within the day (at least once)
    B. CTO is up to date (no need for catch up)
*/
FUNCTION CTO_HAS_FINISHED RETURN INTEGER;

/*
    Logs an entry on table dwadmin.conc_stats_collection_log regarding the concurrent statistics gathering
    
    @parameters:
        startdt input   Start date of stats collection
        enddt_in    input   End date of stats collection
        operation_in    input   Valid values are 'INSERT', 'UPDATE'. It controls the type of "update" to the log table
                                Default 'INSERT'
        message_in  input   A message to be logged                                
*/
PROCEDURE LOG_CONC_STATS_COLLECTION (startdt_in in date, enddt_in in date default null, operation_in varchar2 default 'INSERT', message_in varchar2);

END CONC_STATS_COLLECTION;