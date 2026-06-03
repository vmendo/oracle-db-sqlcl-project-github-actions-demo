WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE ON
SET SERVEROUTPUT ON
SET FEEDBACK ON

DEFINE TARGET_SCHEMA = "&1"

PROMPT Dropping every object in schema &&TARGET_SCHEMA

DECLARE
  v_expected_schema VARCHAR2(128) := UPPER('&&TARGET_SCHEMA');
  v_session_user    VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
BEGIN
  IF v_session_user <> v_expected_schema THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Refusing to drop schema objects. Connected user is ' || v_session_user || ', expected ' || v_expected_schema || '.'
    );
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_expected_schema);
  DBMS_OUTPUT.PUT_LINE('Connected user and target schema validated: ' || v_expected_schema);
END;
/

DECLARE
  v_remaining_objects NUMBER;

  PROCEDURE drop_object(
    p_object_type IN VARCHAR2,
    p_object_name IN VARCHAR2,
    p_statement   IN VARCHAR2
  ) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Dropping ' || p_object_type || ' ' || p_object_name);
    EXECUTE IMMEDIATE p_statement;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Skipped ' || p_object_type || ' ' || p_object_name || ': ' || SQLERRM);
  END;

  FUNCTION qname(p_object_name IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN DBMS_ASSERT.ENQUOTE_NAME(p_object_name, FALSE);
  END;

  PROCEDURE ensure_project_control IS
    l_table_count NUMBER := 0;
  BEGIN
    SELECT COUNT(*)
    INTO   l_table_count
    FROM   user_tables
    WHERE  table_name = 'PROJECT_CONTROL';

    IF l_table_count = 0 THEN
      EXECUTE IMMEDIATE q'[
        CREATE TABLE project_control (
          project_name VARCHAR2(128),
          target_schema VARCHAR2(128),
          release_version VARCHAR2(64),
          release_tag VARCHAR2(128),
          artifact_name VARCHAR2(512),
          artifact_sha256 VARCHAR2(64),
          previous_release_version VARCHAR2(64),
          deployed_at TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
          deployed_by VARCHAR2(256),
          github_repository VARCHAR2(256),
          github_run_id VARCHAR2(64),
          github_run_attempt VARCHAR2(32),
          github_sha VARCHAR2(64),
          deploy_status VARCHAR2(30),
          notes VARCHAR2(4000)
        )
      ]';

      DBMS_OUTPUT.PUT_LINE('Created PROJECT_CONTROL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('PROJECT_CONTROL already exists');
    END IF;
  END;
BEGIN
  ensure_project_control;

  FOR r IN (
    SELECT object_name
    FROM   user_objects
    WHERE  object_type = 'MATERIALIZED VIEW'
    ORDER  BY object_name
  ) LOOP
    drop_object('MATERIALIZED VIEW', r.object_name, 'DROP MATERIALIZED VIEW ' || qname(r.object_name));
  END LOOP;

  FOR r IN (
    SELECT object_name
    FROM   user_objects
    WHERE  object_type = 'VIEW'
    ORDER  BY object_name
  ) LOOP
    drop_object('VIEW', r.object_name, 'DROP VIEW ' || qname(r.object_name));
  END LOOP;

  FOR r IN (
    SELECT trigger_name
    FROM   user_triggers
    WHERE  NVL(table_name, '-') <> 'PROJECT_CONTROL'
    ORDER  BY trigger_name
  ) LOOP
    drop_object('TRIGGER', r.trigger_name, 'DROP TRIGGER ' || qname(r.trigger_name));
  END LOOP;

  FOR r IN (
    SELECT table_name
    FROM   user_tables
    WHERE  table_name <> 'PROJECT_CONTROL'
    ORDER  BY table_name
  ) LOOP
    drop_object('TABLE', r.table_name, 'DROP TABLE ' || qname(r.table_name) || ' CASCADE CONSTRAINTS PURGE');
  END LOOP;

  FOR r IN (
    SELECT index_name
    FROM   user_indexes
    WHERE  table_name <> 'PROJECT_CONTROL'
    ORDER  BY index_name
  ) LOOP
    drop_object('INDEX', r.index_name, 'DROP INDEX ' || qname(r.index_name));
  END LOOP;

  FOR r IN (
    SELECT object_name
    FROM   user_objects
    WHERE  object_type = 'SEQUENCE'
    ORDER  BY object_name
  ) LOOP
    drop_object('SEQUENCE', r.object_name, 'DROP SEQUENCE ' || qname(r.object_name));
  END LOOP;

  FOR r IN (
    SELECT object_name, object_type
    FROM   user_objects
    WHERE  object_type IN ('PACKAGE BODY', 'PACKAGE', 'PROCEDURE', 'FUNCTION')
    ORDER  BY DECODE(object_type, 'PACKAGE BODY', 1, 'PACKAGE', 2, 'PROCEDURE', 3, 'FUNCTION', 4), object_name
  ) LOOP
    drop_object(r.object_type, r.object_name, 'DROP ' || r.object_type || ' ' || qname(r.object_name));
  END LOOP;

  FOR r IN (
    SELECT synonym_name
    FROM   user_synonyms
    ORDER  BY synonym_name
  ) LOOP
    drop_object('SYNONYM', r.synonym_name, 'DROP SYNONYM ' || qname(r.synonym_name));
  END LOOP;

  FOR r IN (
    SELECT db_link
    FROM   user_db_links
    ORDER  BY db_link
  ) LOOP
    drop_object('DATABASE LINK', r.db_link, 'DROP DATABASE LINK ' || qname(r.db_link));
  END LOOP;

  FOR r IN (
    SELECT type_name
    FROM   user_types
    ORDER  BY type_name
  ) LOOP
    drop_object('TYPE', r.type_name, 'DROP TYPE ' || qname(r.type_name) || ' FORCE');
  END LOOP;

  FOR r IN (
    SELECT table_name
    FROM   user_tables
    WHERE  table_name = 'PROJECT_CONTROL'
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('Truncating PROJECT_CONTROL');
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PROJECT_CONTROL';
  END LOOP;

  SELECT COUNT(*)
  INTO   v_remaining_objects
  FROM   user_objects
  WHERE  NOT (object_type = 'TABLE' AND object_name = 'PROJECT_CONTROL');

  IF v_remaining_objects > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Remaining schema objects:');
    FOR r IN (
      SELECT object_type, object_name
      FROM   user_objects
      WHERE  NOT (object_type = 'TABLE' AND object_name = 'PROJECT_CONTROL')
      ORDER  BY object_type, object_name
    ) LOOP
      DBMS_OUTPUT.PUT_LINE(' - ' || r.object_type || ' ' || r.object_name);
    END LOOP;

    RAISE_APPLICATION_ERROR(-20001, 'Schema cleanup did not remove every object.');
  END IF;
END;
/

PURGE RECYCLEBIN;

UNDEFINE TARGET_SCHEMA

PROMPT Schema object cleanup complete
