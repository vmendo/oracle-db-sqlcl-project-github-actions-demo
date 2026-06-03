WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE OFF
SET FEEDBACK ON

ALTER SESSION SET CURRENT_SCHEMA = MYAPP;

CREATE INDEX coaches_team_ix ON coaches (team_id);
CREATE INDEX players_team_ix ON players (team_id);
CREATE INDEX players_status_ix ON players (roster_status);
CREATE INDEX contracts_player_ix ON player_contracts (player_id);
CREATE INDEX contracts_status_ix ON player_contracts (contract_status);
CREATE INDEX agreements_sponsor_ix ON sponsor_agreements (sponsor_id);
CREATE INDEX agreements_team_ix ON sponsor_agreements (team_id);
CREATE INDEX games_team_date_ix ON games (team_id, game_date);
CREATE INDEX stats_game_ix ON player_game_stats (game_id);
CREATE INDEX stats_player_ix ON player_game_stats (player_id);
CREATE INDEX expenses_team_date_ix ON expenses (team_id, expense_date);
CREATE INDEX revenues_team_date_ix ON revenues (team_id, revenue_date);

