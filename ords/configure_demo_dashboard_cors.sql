WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON
SET FEEDBACK ON

DEFINE TARGET_SCHEMA = "&1"
DEFINE ALLOWED_ORIGINS = "&2"

PROMPT Configuring ORDS demo dashboard CORS in &&TARGET_SCHEMA
PROMPT Allowed browser origins: &&ALLOWED_ORIGINS

DECLARE
  l_expected_schema VARCHAR2(128) := UPPER('&&TARGET_SCHEMA');
  l_session_user    VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
BEGIN
  IF l_session_user <> l_expected_schema THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Refusing to configure ORDS dashboard CORS. Connected user is ' || l_session_user || ', expected ' || l_expected_schema || '.'
    );
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_expected_schema);

  ORDS.SET_MODULE_ORIGINS_ALLOWED(
    p_module_name     => 'myapp.demo_dashboard',
    p_origins_allowed => '&&ALLOWED_ORIGINS'
  );

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Configured CORS origins for myapp.demo_dashboard.');
END;
/

UNDEFINE TARGET_SCHEMA
UNDEFINE ALLOWED_ORIGINS

PROMPT ORDS demo dashboard CORS configuration complete
