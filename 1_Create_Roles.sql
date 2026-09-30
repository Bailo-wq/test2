DO
$do$
BEGIN
   IF EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = 'user_name"') THEN

      RAISE NOTICE 'Role "username" already exists. Skipping.';
   ELSE
      BEGIN
         CREATE ROLE username;
         ALTER ROLE username WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'password_admin';
         RAISE NOTICE 'Role "username" created without issues';
      EXCEPTION
         WHEN duplicate_object THEN
            RAISE NOTICE 'Role "username" was just created by a concurrent transaction. Skipping.';
      END;
   END IF;
END
$do$;
