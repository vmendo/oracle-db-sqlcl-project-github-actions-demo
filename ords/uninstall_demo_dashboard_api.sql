WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON
SET FEEDBACK ON

DEFINE TARGET_SCHEMA = "&1"

PROMPT Removing ORDS demo dashboard API from &&TARGET_SCHEMA

DECLARE
  l_expected_schema VARCHAR2(128) := UPPER('&&TARGET_SCHEMA');
  l_session_user    VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
BEGIN
  IF l_session_user <> l_expected_schema THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Refusing to remove ORDS dashboard API. Connected user is ' || l_session_user || ', expected ' || l_expected_schema || '.'
    );
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_expected_schema);
END;
/

BEGIN
  ORDS.DELETE_MODULE(p_module_name => 'myapp.demo_dashboard');
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Removed ORDS module myapp.demo_dashboard.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ORDS module removal skipped: ' || SQLERRM);
END;
/

UNDEFINE TARGET_SCHEMA

PROMPT ORDS demo dashboard API removal complete
