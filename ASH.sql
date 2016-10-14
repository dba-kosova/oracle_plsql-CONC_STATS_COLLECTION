select sql_id, sum(10)/60 min
from dba_hist_active_sess_history t
where
t.user_id in (select user_id from dba_users where username = 'SYS')
AND module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
and sample_time between to_date('20-11-2013 16:00:00', 'dd-mm-yyyy hh24:mi:ss') and to_date('20-11-2013 23:59:59', 'dd-mm-yyyy hh24:mi:ss')
group by sql_id
order by 2 desc


select sql_id, sum(1)/60 mins
from v$active_session_history t
where
t.user_id in (select user_id from dba_users where username = 'SYS')
AND module = 'DBMS_SCHEDULER' and session_type = 'FOREGROUND'
and sample_time between to_date('20-11-2013 16:00:00', 'dd-mm-yyyy hh24:mi:ss') and to_date('20-11-2013 23:59:59', 'dd-mm-yyyy hh24:mi:ss')
group by sql_id
order by 2 desc