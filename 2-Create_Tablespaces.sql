---------- DATA -----------
DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_tablespace
        WHERE spcname ='tbs_xxx_data' ) THEN
      RAISE NOTICE 'Tablespace "tbs_xxx_data" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating Tablespace "tbs_xxx_data" ...';
  END IF;

END
$do$;

SELECT 'CREATE TABLESPACE tbs_xxx_data OWNER postgres LOCATION ''/pgdata/tbs_xxx_data''  '
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_data')\gexec

GRANT ALL ON TABLESPACE tbs_xxx_data TO xxx_admin;
GRANT ALL ON TABLESPACE tbs_xxx_data TO xxx_user;
GRANT ALL ON TABLESPACE tbs_xxx_data TO xxx_exploit;

DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_tablespace
        WHERE spcname ='tbs_repmgr_data' ) THEN
      RAISE NOTICE 'Tablespace "tbs_repmgr_data" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating Tablespace "tbs_repmgr_data" ...';
  END IF;

END
$do$;

SELECT 'CREATE TABLESPACE tbs_repmgr_data OWNER postgres LOCATION ''/pgdata/tbs_repmgr_data''  '
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_repmgr_data')\gexec

GRANT ALL ON TABLESPACE tbs_repmgr_data TO repuser;
---------- INDEX -----------
DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_tablespace
        WHERE spcname ='tbs_xxx_indx' ) THEN
      RAISE NOTICE 'Tablespace "tbs_xxx_indx" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating Tablespace "tbs_xxx_indx" ...';
  END IF;

END
$do$;

SELECT 'CREATE TABLESPACE tbs_xxx_indx OWNER postgres LOCATION ''/pgindx/tbs_xxx_indx''  '
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_indx')\gexec

GRANT ALL ON TABLESPACE tbs_xxx_indx TO xxx_admin;
GRANT ALL ON TABLESPACE tbs_xxx_indx TO xxx_user;
GRANT ALL ON TABLESPACE tbs_xxx_indx TO xxx_exploit;
---------- TEMP -----------
DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_tablespace
        WHERE spcname ='tbs_xxx_temp' ) THEN
      RAISE NOTICE 'Tablespace "tbs_xxx_temp" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating Tablespace "tbs_xxx_temp" ...';
  END IF;

END
$do$;

SELECT 'CREATE TABLESPACE tbs_xxx_temp OWNER postgres LOCATION ''/pgtemp/tbs_xxx_temp''  '
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_temp')\gexec

GRANT ALL ON TABLESPACE tbs_xxx_temp TO xxx_admin;
GRANT ALL ON TABLESPACE tbs_xxx_temp TO xxx_user;
GRANT ALL ON TABLESPACE tbs_xxx_temp TO xxx_exploit;
~
