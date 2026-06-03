WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE OFF
SET FEEDBACK ON

ALTER SESSION SET CURRENT_SCHEMA = MYAPP;

ALTER TABLE games ADD (
  attendance            NUMBER(7),
  ticket_revenue_amount NUMBER(12,2)
);

ALTER TABLE games ADD CONSTRAINT games_attendance_ck CHECK (attendance IS NULL OR attendance >= 0);
ALTER TABLE games ADD CONSTRAINT games_ticket_rev_ck CHECK (ticket_revenue_amount IS NULL OR ticket_revenue_amount >= 0);

