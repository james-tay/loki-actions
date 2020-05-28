# Overview
This is my attempt to re-create saved searches which are typically available in Splunk.
The "loki-actions" utility reads the "loki-actions.yaml" config file, and implements the workflow described by the user.
Typically this will involve performing various searches against the loki backend.
If matches occur, some user defined action is typically executed. 
The "loki-actions" utility is typically run from cron.
