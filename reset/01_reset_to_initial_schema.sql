WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE OFF
SET SERVEROUTPUT ON
SET FEEDBACK ON

ALTER SESSION SET CURRENT_SCHEMA = MYAPP;

PROMPT Resetting MYAPP demo schema to the initial baseline

DECLARE
  FUNCTION table_exists(p_table_name IN VARCHAR2) RETURN BOOLEAN IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*)
    INTO   v_count
    FROM   user_tables
    WHERE  table_name = UPPER(p_table_name);

    RETURN v_count > 0;
  END;

  FUNCTION column_exists(
    p_table_name  IN VARCHAR2,
    p_column_name IN VARCHAR2
  ) RETURN BOOLEAN IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*)
    INTO   v_count
    FROM   user_tab_cols
    WHERE  table_name  = UPPER(p_table_name)
    AND    column_name = UPPER(p_column_name);

    RETURN v_count > 0;
  END;

  FUNCTION constraint_exists(
    p_table_name      IN VARCHAR2,
    p_constraint_name IN VARCHAR2
  ) RETURN BOOLEAN IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*)
    INTO   v_count
    FROM   user_constraints
    WHERE  table_name      = UPPER(p_table_name)
    AND    constraint_name = UPPER(p_constraint_name);

    RETURN v_count > 0;
  END;

  PROCEDURE drop_table_if_exists(p_table_name IN VARCHAR2) IS
  BEGIN
    IF table_exists(p_table_name) THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || p_table_name || ' PURGE';
      DBMS_OUTPUT.PUT_LINE('Dropped table ' || UPPER(p_table_name));
    ELSE
      DBMS_OUTPUT.PUT_LINE('Table ' || UPPER(p_table_name) || ' not present');
    END IF;
  END;

  PROCEDURE drop_constraint_if_exists(
    p_table_name      IN VARCHAR2,
    p_constraint_name IN VARCHAR2
  ) IS
  BEGIN
    IF constraint_exists(p_table_name, p_constraint_name) THEN
      EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' DROP CONSTRAINT ' || p_constraint_name;
      DBMS_OUTPUT.PUT_LINE('Dropped constraint ' || UPPER(p_constraint_name));
    ELSE
      DBMS_OUTPUT.PUT_LINE('Constraint ' || UPPER(p_constraint_name) || ' not present');
    END IF;
  END;

  PROCEDURE drop_column_if_exists(
    p_table_name  IN VARCHAR2,
    p_column_name IN VARCHAR2
  ) IS
  BEGIN
    IF column_exists(p_table_name, p_column_name) THEN
      EXECUTE IMMEDIATE 'ALTER TABLE ' || p_table_name || ' DROP COLUMN ' || p_column_name;
      DBMS_OUTPUT.PUT_LINE('Dropped column ' || UPPER(p_table_name) || '.' || UPPER(p_column_name));
    ELSE
      DBMS_OUTPUT.PUT_LINE('Column ' || UPPER(p_table_name) || '.' || UPPER(p_column_name) || ' not present');
    END IF;
  END;
BEGIN
  drop_table_if_exists('INJURY_REPORTS');
  drop_table_if_exists('TRAINING_SESSIONS');

  drop_constraint_if_exists('GAMES', 'GAMES_TICKET_REV_CK');
  drop_constraint_if_exists('GAMES', 'GAMES_ATTENDANCE_CK');
  drop_column_if_exists('GAMES', 'TICKET_REVENUE_AMOUNT');
  drop_column_if_exists('GAMES', 'ATTENDANCE');

  drop_column_if_exists('PLAYERS', 'SOCIAL_MEDIA_HANDLE');

  IF column_exists('EXPENSES', 'PAYEE_NAME') AND NOT column_exists('EXPENSES', 'VENDOR_NAME') THEN
    EXECUTE IMMEDIATE 'ALTER TABLE expenses RENAME COLUMN payee_name TO vendor_name';
    DBMS_OUTPUT.PUT_LINE('Renamed EXPENSES.PAYEE_NAME back to VENDOR_NAME');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXPENSES vendor column already in baseline state');
  END IF;
END;
/

PROMPT Reset complete

