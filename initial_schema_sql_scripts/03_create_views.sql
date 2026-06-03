WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE OFF
SET FEEDBACK ON

ALTER SESSION SET CURRENT_SCHEMA = MYAPP;

CREATE OR REPLACE VIEW vw_player_salary_summary AS
SELECT p.player_id,
       p.team_id,
       p.jersey_number,
       p.first_name || ' ' || p.last_name AS player_name,
       p.player_position,
       p.roster_status,
       COUNT(pc.contract_id) AS contract_count,
       SUM(CASE WHEN pc.contract_status = 'ACTIVE' THEN pc.salary_amount ELSE 0 END) AS active_salary_amount,
       SUM(CASE WHEN pc.contract_status = 'ACTIVE' THEN pc.bonus_amount ELSE 0 END) AS active_bonus_amount
FROM   players p
       LEFT JOIN player_contracts pc ON pc.player_id = p.player_id
GROUP  BY p.player_id,
          p.team_id,
          p.jersey_number,
          p.first_name,
          p.last_name,
          p.player_position,
          p.roster_status;

CREATE OR REPLACE VIEW vw_game_box_scores AS
SELECT g.game_id,
       g.team_id,
       g.opponent_name,
       g.game_date,
       g.venue_type,
       g.team_score,
       g.opponent_score,
       COUNT(s.stat_id) AS players_with_stats,
       SUM(s.points) AS total_player_points,
       SUM(s.rebounds) AS total_rebounds,
       SUM(s.assists) AS total_assists,
       SUM(s.turnovers) AS total_turnovers
FROM   games g
       LEFT JOIN player_game_stats s ON s.game_id = g.game_id
GROUP  BY g.game_id,
          g.team_id,
          g.opponent_name,
          g.game_date,
          g.venue_type,
          g.team_score,
          g.opponent_score;

CREATE OR REPLACE VIEW vw_team_financial_summary AS
SELECT team_id,
       financial_month,
       SUM(revenue_amount) AS revenue_amount,
       SUM(expense_amount) AS expense_amount,
       SUM(revenue_amount) - SUM(expense_amount) AS net_amount
FROM (
  SELECT team_id,
         TRUNC(revenue_date, 'MM') AS financial_month,
         amount AS revenue_amount,
         0 AS expense_amount
  FROM   revenues
  UNION ALL
  SELECT team_id,
         TRUNC(expense_date, 'MM') AS financial_month,
         0 AS revenue_amount,
         amount AS expense_amount
  FROM   expenses
)
GROUP BY team_id, financial_month;

