DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_database
        WHERE datname ='xxx' ) THEN
      RAISE NOTICE 'Database "xxx" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating database "xxx" ...';
  END IF;

END
$do$;

-- database grant
SELECT 'CREATE DATABASE xxx WITH TEMPLATE = template0 ENCODING = ''UTF8'' LC_COLLATE = ''fr_FR.UTF-8'' LC_CTYPE = ''fr_FR.UTF-8'' TABLESPACE = tbs_xxx_data'
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = 'xxx')\gexec

ALTER DATABASE xxx OWNER TO postgres;

GRANT CONNECT ON DATABASE xxx TO xxx_user;
GRANT CONNECT ON DATABASE xxx TO xxx_admin;
GRANT CONNECT ON DATABASE xxx TO xxx_exploit;
GRANT CONNECT ON DATABASE xxx TO zbx_monitor;
GRANT CONNECT ON DATABASE xxx TO pmm_user;
GRANT CONNECT ON DATABASE xxx TO barman;
GRANT CONNECT ON DATABASE xxx TO u_pgsqlexe;
GRANT ALL ON DATABASE xxx TO xxx_admin;

/*
SELECT 'ALTER DATABASE xxx SET TABLESPACE tbs_xxx_data '
WHERE EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_data')\gexec
*/

SELECT 'ALTER DATABASE xxx SET default_tablespace TO ''tbs_xxx_data'' '
WHERE EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_data')\gexec

SELECT 'ALTER DATABASE xxx SET temp_tablespaces TO ''tbs_xxx_temp''  '
WHERE EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_temp')\gexec

ALTER ROLE xxx_admin IN DATABASE xxx SET search_path TO '$user', 'public', 'xxx_admin';
ALTER ROLE xxx_user IN DATABASE xxx SET search_path TO '$user', 'public', 'xxx_admin';
ALTER ROLE xxx_exploit IN DATABASE xxx SET search_path TO '$user', 'public', 'xxx_admin';
ALTER ROLE postgres IN DATABASE xxx SET search_path TO '$user','public', 'xxx_admin';
ALTER ROLE zbx_monitor IN DATABASE xxx SET search_path TO '$user','public', 'xxx_admin';
ALTER ROLE u_pgsqlexe IN DATABASE xxx SET search_path TO '$user','public', 'xxx_admin';
ALTER ROLE pmm_user IN DATABASE xxx SET search_path TO '$user','public', 'xxx_admin';
ALTER ROLE barman IN DATABASE xxx SET search_path TO '$user','public', 'xxx_admin';

-- Creation de la base repmgr
DO
$do$
BEGIN
  IF EXISTS (
        SELECT FROM pg_catalog.pg_database
        WHERE datname ='repmgr' ) THEN
      RAISE NOTICE 'Database "repmgr" already exists. Skipping.';
  ELSE
      RAISE NOTICE 'Creating database "repmgr" ...';
  END IF;

END
$do$;

SELECT 'CREATE DATABASE repmgr WITH TEMPLATE = template0 ENCODING = ''UTF8'' LC_COLLATE = ''fr_FR.UTF-8'' LC_CTYPE = ''fr_FR.UTF-8'' TABLESPACE = tbs_repmgr_data'
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = 'repmgr')\gexec

ALTER DATABASE repmgr OWNER TO postgres;

SELECT 'ALTER DATABASE repmgr SET default_tablespace TO ''tbs_repmgr_data'' '
WHERE EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_repmgr_data')\gexec

SELECT 'ALTER DATABASE repmgr SET temp_tablespaces TO ''tbs_xxx_temp''  '
WHERE EXISTS (SELECT FROM pg_catalog.pg_tablespace WHERE spcname ='tbs_xxx_temp')\gexec

REVOKE CONNECT,TEMPORARY ON DATABASE repmgr FROM PUBLIC;
GRANT TEMPORARY ON DATABASE repmgr TO PUBLIC;
GRANT CONNECT ON DATABASE repmgr TO zbx_monitor;
GRANT CONNECT ON DATABASE repmgr TO barman;
GRANT CONNECT ON DATABASE repmgr TO pmm_user;

-- Creation des schemas applicatives
\connect xxx
\connect xxx
----------- schema admin -----------
CREATE SCHEMA IF NOT EXISTS xxx_admin AUTHORIZATION xxx_admin;
ALTER SCHEMA xxx_admin OWNER TO xxx_admin;
GRANT USAGE,CREATE ON SCHEMA xxx_admin TO xxx_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES in schema xxx_admin to xxx_admin;
GRANT USAGE ON SCHEMA xxx_admin TO xxx_user;
REVOKE CREATE ON schema xxx_admin FROM xxx_user;
GRANT ALL ON SCHEMA xxx_admin TO postgres;
GRANT USAGE ON SCHEMA xxx_admin TO u_pgsqlexe ;
GRANT ALL PRIVILEGES ON ALL SEQUENCES in schema xxx_admin to u_pgsqlexe ;
GRANT SELECT,INSERT,DELETE,UPDATE ON ALL TABLES in schema xxx_admin to u_pgsqlexe ;

----------- schema user -----------
CREATE SCHEMA IF NOT EXISTS xxx_user AUTHORIZATION xxx_user;
ALTER SCHEMA xxx_user OWNER TO xxx_user;
GRANT ALL ON SCHEMA xxx_user TO postgres;
GRANT USAGE ON SCHEMA xxx_user TO xxx_admin;
REVOKE CREATE ON schema xxx_user FROM xxx_user;
GRANT USAGE,SELECT ON ALL SEQUENCES in SCHEMA xxx_admin to xxx_user;
GRANT SELECT ON ALL TABLES in SCHEMA xxx_admin to xxx_user;

----------- schema  exploit ---
CREATE SCHEMA IF NOT EXISTS xxx_exploit AUTHORIZATION xxx_exploit;
ALTER SCHEMA xxx_exploit OWNER TO xxx_exploit;
REVOKE ALL ON SCHEMA xxx_exploit FROM xxx_exploit;
GRANT USAGE ON SCHEMA xxx_exploit TO xxx_exploit;
GRANT USAGE ON SCHEMA xxx_admin TO xxx_exploit;
GRANT USAGE,SELECT ON ALL SEQUENCES in SCHEMA xxx_admin to xxx_exploit;
GRANT ALL PRIVILEGES ON ALL TABLES in schema xxx_admin to xxx_exploit ;
GRANT ALL ON ALL FUNCTIONS in schema xxx_admin to xxx_exploit ;
GRANT EXECUTE ON ALL PROCEDURES in schema xxx_admin to xxx_exploit ;

----------- schema u_pgsqlexe ---
CREATE SCHEMA IF NOT EXISTS u_pgsqlexe AUTHORIZATION u_pgsqlexe;
ALTER SCHEMA u_pgsqlexe OWNER TO u_pgsqlexe;
REVOKE ALL ON SCHEMA u_pgsqlexe FROM u_pgsqlexe;
GRANT USAGE ON SCHEMA u_pgsqlexe TO u_pgsqlexe;

-- create necessary extension for database
CREATE EXTENSION IF NOT EXISTS pageinspect WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_buffercache WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_freespacemap WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_prewarm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgrowlocks WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA public;
COMMENT ON EXTENSION pageinspect IS 'inspect the contents of database pages at a low level';
COMMENT ON EXTENSION pg_buffercache IS 'examine the shared buffer cache';
COMMENT ON EXTENSION pg_freespacemap IS 'examine the free space map (FSM)';
COMMENT ON EXTENSION pg_prewarm IS 'prewarm relation data';
COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';
COMMENT ON EXTENSION pgrowlocks IS 'show row-level locking information';
COMMENT ON EXTENSION pgstattuple IS 'show tuple-level statistics';


--- Les privileges pardefaut
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE ON TABLES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT USAGE,SELECT ON SEQUENCES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON FUNCTIONS  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT EXECUTE ON ROUTINES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_exploit IN SCHEMA xxx_admin GRANT ALL ON FUNCTIONS  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_exploit IN SCHEMA xxx_admin GRANT EXECUTE ON ROUTINES TO xxx_exploit;

--- Les privileges pardefaut
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE ON TABLES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT USAGE,SELECT ON SEQUENCES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT ALL ON FUNCTIONS  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_admin IN SCHEMA xxx_admin GRANT EXECUTE ON ROUTINES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_exploit IN SCHEMA xxx_admin GRANT ALL ON FUNCTIONS  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE xxx_exploit IN SCHEMA xxx_admin GRANT EXECUTE ON ROUTINES TO xxx_exploit;

ALTER DEFAULT PRIVILEGES FOR ROLE u_pgsqlexe IN SCHEMA xxx_admin GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO u_pgsqlexe;

----------- default privs for postgres
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE ON TABLES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT SELECT,INSERT,UPDATE, DELETE,TRUNCATE ON TABLES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT USAGE,SELECT ON SEQUENCES TO xxx_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES TO xxx_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT ALL ON SEQUENCES  TO u_pgsqlexe;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT ALL ON FUNCTIONS  TO xxx_exploit;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA xxx_admin GRANT EXECUTE ON ROUTINES  TO xxx_exploit;

\connect repmgr
CREATE SCHEMA IF NOT EXISTS repmgr AUTHORIZATION repuser;
ALTER SCHEMA repmgr OWNER TO repuser;

CREATE EXTENSION IF NOT EXISTS repmgr WITH SCHEMA repmgr;
COMMENT ON EXTENSION repmgr IS 'Replication manager for PostgreSQL';

\connect postgres
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;
COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';

                                                                                                                                 
