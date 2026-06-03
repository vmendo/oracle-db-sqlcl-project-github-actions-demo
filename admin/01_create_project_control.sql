WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE OFF
SET SERVEROUTPUT ON
SET FEEDBACK ON

PROMPT Ensuring PROJECT_CONTROL exists in the connected schema

DECLARE
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

    DBMS_OUTPUT.PUT_LINE('Created PROJECT_CONTROL.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('PROJECT_CONTROL already exists.');
  END IF;
END;
/

PROMPT PROJECT_CONTROL is ready
