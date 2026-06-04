WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
WHENEVER OSERROR EXIT 9 ROLLBACK

SET DEFINE ON
SET SERVEROUTPUT ON
SET FEEDBACK ON

DEFINE TARGET_SCHEMA = "&1"

PROMPT Installing read-only ORDS demo dashboard API in &&TARGET_SCHEMA

DECLARE
  l_expected_schema VARCHAR2(128) := UPPER('&&TARGET_SCHEMA');
  l_session_user    VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
BEGIN
  IF l_session_user <> l_expected_schema THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Refusing to install ORDS dashboard API. Connected user is ' || l_session_user || ', expected ' || l_expected_schema || '.'
    );
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_expected_schema);
  DBMS_OUTPUT.PUT_LINE('Connected user and target schema validated: ' || l_expected_schema);
END;
/

DECLARE
  l_schema      VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
  l_module_name CONSTANT VARCHAR2(128) := 'myapp.demo_dashboard';

  PROCEDURE define_plsql_handler(
    p_pattern  IN VARCHAR2,
    p_comments IN VARCHAR2,
    p_source   IN CLOB
  ) IS
  BEGIN
    ORDS.DEFINE_TEMPLATE(
      p_module_name => l_module_name,
      p_pattern     => p_pattern,
      p_comments    => p_comments
    );

    ORDS.DEFINE_HANDLER(
      p_module_name    => l_module_name,
      p_pattern        => p_pattern,
      p_method         => 'GET',
      p_source_type    => ORDS.source_type_plsql,
      p_items_per_page => 0,
      p_comments       => p_comments,
      p_source         => p_source
    );
  END;
BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => l_schema,
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => LOWER(l_schema),
    p_auto_rest_auth      => FALSE
  );

  BEGIN
    ORDS.DELETE_MODULE(p_module_name => l_module_name);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  ORDS.DEFINE_MODULE(
    p_module_name    => l_module_name,
    p_base_path      => '/demo-dashboard/',
    p_items_per_page => 100,
    p_status         => 'PUBLISHED',
    p_comments       => 'Read-only dashboard endpoints for the SQLcl Projects CI/CD demo'
  );

  define_plsql_handler(
    p_pattern  => 'health/',
    p_comments => 'Environment health and metadata',
    p_source   => q'~
DECLARE
  l_json CLOB;
BEGIN
  SELECT JSON_OBJECT(
           'schemaName' VALUE SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),
           'sessionUser' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
           'databaseName' VALUE SYS_CONTEXT('USERENV', 'DB_NAME'),
           'serverTime' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'),
           'projectControlExists' VALUE CASE WHEN EXISTS (
             SELECT 1 FROM user_tables WHERE table_name = 'PROJECT_CONTROL'
           ) THEN 'Y' ELSE 'N' END,
           'databaseChangelogExists' VALUE CASE WHEN EXISTS (
             SELECT 1 FROM user_tables WHERE table_name = 'DATABASECHANGELOG'
           ) THEN 'Y' ELSE 'N' END,
           'invalidObjectCount' VALUE (
             SELECT COUNT(*) FROM user_objects WHERE status <> 'VALID'
           )
           RETURNING CLOB
         )
  INTO   l_json
  FROM   dual;

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  define_plsql_handler(
    p_pattern  => 'summary/',
    p_comments => 'Aggregated schema and deployment summary',
    p_source   => q'~
DECLARE
  l_object_counts     CLOB := '[]';
  l_latest_deployment CLOB := 'null';
  l_latest_changeset  CLOB := 'null';
  l_json              CLOB;
  l_table_count       NUMBER;
BEGIN
  SELECT COALESCE(
           JSON_ARRAYAGG(
             JSON_OBJECT(
               'objectType' VALUE object_type,
               'totalCount' VALUE total_count,
               'invalidCount' VALUE invalid_count
               RETURNING CLOB
             )
             ORDER BY object_type
             RETURNING CLOB
           ),
           '[]'
         )
  INTO   l_object_counts
  FROM (
    SELECT object_type,
           COUNT(*) total_count,
           SUM(CASE WHEN status <> 'VALID' THEN 1 ELSE 0 END) invalid_count
    FROM   user_objects
    GROUP  BY object_type
  );

  SELECT COUNT(*)
  INTO   l_table_count
  FROM   user_tables
  WHERE  table_name = 'PROJECT_CONTROL';

  IF l_table_count > 0 THEN
    EXECUTE IMMEDIATE q'[
      SELECT COALESCE(
               (
                 SELECT JSON_OBJECT(
                          'projectName' VALUE project_name,
                          'targetSchema' VALUE target_schema,
                          'releaseVersion' VALUE release_version,
                          'releaseTag' VALUE release_tag,
                          'artifactName' VALUE artifact_name,
                          'artifactSha256' VALUE artifact_sha256,
                          'previousReleaseVersion' VALUE previous_release_version,
                          'deployedAt' VALUE TO_CHAR(deployed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'),
                          'deployedBy' VALUE deployed_by,
                          'githubRepository' VALUE github_repository,
                          'githubRunId' VALUE github_run_id,
                          'githubRunAttempt' VALUE github_run_attempt,
                          'githubSha' VALUE github_sha,
                          'deployStatus' VALUE deploy_status,
                          'notes' VALUE notes
                          RETURNING CLOB
                        )
                 FROM (
                   SELECT *
                   FROM   project_control
                   ORDER  BY deployed_at DESC NULLS LAST
                   FETCH FIRST 1 ROW ONLY
                 )
               ),
               'null'
             )
      FROM dual
    ]' INTO l_latest_deployment;
  END IF;

  SELECT COUNT(*)
  INTO   l_table_count
  FROM   user_tables
  WHERE  table_name = 'DATABASECHANGELOG';

  IF l_table_count > 0 THEN
    EXECUTE IMMEDIATE q'[
      SELECT COALESCE(
               (
                 SELECT JSON_OBJECT(
                          'id' VALUE id,
                          'author' VALUE author,
                          'filename' VALUE filename,
                          'dateExecuted' VALUE TO_CHAR(dateexecuted, 'YYYY-MM-DD"T"HH24:MI:SS'),
                          'orderExecuted' VALUE orderexecuted,
                          'execType' VALUE exectype,
                          'description' VALUE description
                          RETURNING CLOB
                        )
                 FROM (
                   SELECT *
                   FROM   databasechangelog
                   ORDER  BY orderexecuted DESC
                   FETCH FIRST 1 ROW ONLY
                 )
               ),
               'null'
             )
      FROM dual
    ]' INTO l_latest_changeset;
  END IF;

  SELECT JSON_OBJECT(
           'schemaName' VALUE SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),
           'serverTime' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'),
           'objectCounts' VALUE l_object_counts FORMAT JSON,
           'latestDeployment' VALUE l_latest_deployment FORMAT JSON,
           'latestChangeset' VALUE l_latest_changeset FORMAT JSON
           RETURNING CLOB
         )
  INTO   l_json
  FROM   dual;

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  define_plsql_handler(
    p_pattern  => 'objects/',
    p_comments => 'Schema objects with application or metadata classification',
    p_source   => q'~
DECLARE
  l_json CLOB;
BEGIN
  SELECT JSON_OBJECT(
           'items' VALUE COALESCE(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'objectName' VALUE object_name,
                 'objectType' VALUE object_type,
                 'status' VALUE status,
                 'objectGroup' VALUE object_group,
                 'created' VALUE TO_CHAR(created, 'YYYY-MM-DD"T"HH24:MI:SS'),
                 'lastDdlTime' VALUE TO_CHAR(last_ddl_time, 'YYYY-MM-DD"T"HH24:MI:SS')
                 RETURNING CLOB
               )
               ORDER BY object_group, object_type, object_name
               RETURNING CLOB
             ),
             '[]'
           ) FORMAT JSON
           RETURNING CLOB
         )
  INTO   l_json
  FROM (
    SELECT object_name,
           object_type,
           status,
           created,
           last_ddl_time,
           CASE
             WHEN object_name = 'PROJECT_CONTROL'
               OR object_name LIKE 'DATABASECHANGELOG%'
               OR object_name LIKE 'DBTOOLS$%'
             THEN 'DEMO_METADATA'
             ELSE 'APPLICATION'
           END object_group
    FROM   user_objects
  );

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  define_plsql_handler(
    p_pattern  => 'tables/',
    p_comments => 'Table columns, data types, and key flags',
    p_source   => q'~
DECLARE
  l_json CLOB;
BEGIN
  SELECT JSON_OBJECT(
           'items' VALUE COALESCE(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'tableName' VALUE table_name,
                 'columnId' VALUE column_id,
                 'columnName' VALUE column_name,
                 'dataType' VALUE data_type,
                 'dataLength' VALUE data_length,
                 'dataPrecision' VALUE data_precision,
                 'dataScale' VALUE data_scale,
                 'dataTypeDisplay' VALUE data_type_display,
                 'nullable' VALUE nullable,
                 'isPrimaryKey' VALUE is_primary_key,
                 'isForeignKey' VALUE is_foreign_key,
                 'objectGroup' VALUE object_group
                 RETURNING CLOB
               )
               ORDER BY object_group, table_name, column_id
               RETURNING CLOB
             ),
             '[]'
           ) FORMAT JSON
           RETURNING CLOB
         )
  INTO   l_json
  FROM (
    WITH key_columns AS (
      SELECT acc.table_name,
             acc.column_name,
             MAX(CASE WHEN ac.constraint_type = 'P' THEN 'Y' ELSE 'N' END) is_primary_key,
             MAX(CASE WHEN ac.constraint_type = 'R' THEN 'Y' ELSE 'N' END) is_foreign_key
      FROM   user_cons_columns acc
      JOIN   user_constraints ac
      ON     ac.constraint_name = acc.constraint_name
      WHERE  ac.constraint_type IN ('P', 'R')
      GROUP  BY acc.table_name, acc.column_name
    )
    SELECT utc.table_name,
           utc.column_id,
           utc.column_name,
           utc.data_type,
           utc.data_length,
           utc.data_precision,
           utc.data_scale,
           CASE
             WHEN utc.data_type IN ('VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR')
             THEN utc.data_type || '(' || utc.char_length || ')'
             WHEN utc.data_type = 'NUMBER' AND utc.data_precision IS NOT NULL AND utc.data_scale IS NOT NULL
             THEN utc.data_type || '(' || utc.data_precision || ',' || utc.data_scale || ')'
             WHEN utc.data_type = 'NUMBER' AND utc.data_precision IS NOT NULL
             THEN utc.data_type || '(' || utc.data_precision || ')'
             ELSE utc.data_type
           END data_type_display,
           utc.nullable,
           COALESCE(kc.is_primary_key, 'N') is_primary_key,
           COALESCE(kc.is_foreign_key, 'N') is_foreign_key,
           CASE
             WHEN utc.table_name = 'PROJECT_CONTROL'
               OR utc.table_name LIKE 'DATABASECHANGELOG%'
               OR utc.table_name LIKE 'DBTOOLS$%'
             THEN 'DEMO_METADATA'
             ELSE 'APPLICATION'
           END object_group
    FROM   user_tab_columns utc
    JOIN   user_tables ut
    ON     ut.table_name = utc.table_name
    LEFT   JOIN key_columns kc
    ON     kc.table_name = utc.table_name
    AND    kc.column_name = utc.column_name
  );

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  define_plsql_handler(
    p_pattern  => 'changelog/',
    p_comments => 'SQLcl Project and Liquibase changelog rows',
    p_source   => q'~
DECLARE
  l_json        CLOB := '{"items":[]}';
  l_table_count NUMBER;
BEGIN
  SELECT COUNT(*)
  INTO   l_table_count
  FROM   user_tables
  WHERE  table_name = 'DATABASECHANGELOG';

  IF l_table_count > 0 THEN
    EXECUTE IMMEDIATE q'[
      SELECT JSON_OBJECT(
               'items' VALUE COALESCE(
                 JSON_ARRAYAGG(
                   JSON_OBJECT(
                     'id' VALUE id,
                     'author' VALUE author,
                     'filename' VALUE filename,
                     'dateExecuted' VALUE TO_CHAR(dateexecuted, 'YYYY-MM-DD"T"HH24:MI:SS'),
                     'orderExecuted' VALUE orderexecuted,
                     'execType' VALUE exectype,
                     'description' VALUE description,
                     'comments' VALUE comments,
                     'tag' VALUE tag,
                     'liquibase' VALUE liquibase
                     RETURNING CLOB
                   )
                   ORDER BY orderexecuted DESC
                   RETURNING CLOB
                 ),
                 '[]'
               ) FORMAT JSON
               RETURNING CLOB
             )
      FROM (
        SELECT *
        FROM   databasechangelog
        ORDER  BY orderexecuted DESC
        FETCH FIRST 80 ROWS ONLY
      )
    ]' INTO l_json;
  END IF;

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  define_plsql_handler(
    p_pattern  => 'project-control/',
    p_comments => 'Production deployment control history',
    p_source   => q'~
DECLARE
  l_json        CLOB := '{"items":[]}';
  l_table_count NUMBER;
BEGIN
  SELECT COUNT(*)
  INTO   l_table_count
  FROM   user_tables
  WHERE  table_name = 'PROJECT_CONTROL';

  IF l_table_count > 0 THEN
    EXECUTE IMMEDIATE q'[
      SELECT JSON_OBJECT(
               'items' VALUE COALESCE(
                 JSON_ARRAYAGG(
                   JSON_OBJECT(
                     'projectName' VALUE project_name,
                     'targetSchema' VALUE target_schema,
                     'releaseVersion' VALUE release_version,
                     'releaseTag' VALUE release_tag,
                     'artifactName' VALUE artifact_name,
                     'artifactSha256' VALUE artifact_sha256,
                     'previousReleaseVersion' VALUE previous_release_version,
                     'deployedAt' VALUE TO_CHAR(deployed_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'),
                     'deployedBy' VALUE deployed_by,
                     'githubRepository' VALUE github_repository,
                     'githubRunId' VALUE github_run_id,
                     'githubRunAttempt' VALUE github_run_attempt,
                     'githubSha' VALUE github_sha,
                     'deployStatus' VALUE deploy_status,
                     'notes' VALUE notes
                     RETURNING CLOB
                   )
                   ORDER BY deployed_at DESC NULLS LAST
                   RETURNING CLOB
                 ),
                 '[]'
               ) FORMAT JSON
               RETURNING CLOB
             )
      FROM (
        SELECT *
        FROM   project_control
        ORDER  BY deployed_at DESC NULLS LAST
        FETCH FIRST 50 ROWS ONLY
      )
    ]' INTO l_json;
  END IF;

  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(l_json);
END;
~'
  );

  BEGIN
    EXECUTE IMMEDIATE q'[
      BEGIN
        ORDS.SET_MODULE_ORIGINS_ALLOWED(
          p_module_name     => :module_name,
          p_origins_allowed => :origins_allowed
        );
      END;
    ]' USING l_module_name, '*';
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('CORS origin configuration skipped: ' || SQLERRM);
  END;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Installed module /demo-dashboard/ for schema ' || l_schema);
END;
/

UNDEFINE TARGET_SCHEMA

PROMPT ORDS demo dashboard API installation complete
