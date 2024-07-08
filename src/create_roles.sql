--
--  Script Name:	create_roles
--

BEGIN;

  CREATE ROLE kadaster LOGIN
  ENCRYPTED PASSWORD 'kadaster**'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;


  CREATE ROLE kadaster_admin LOGIN
  ENCRYPTED PASSWORD '**kadaster**'
  NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;

END;