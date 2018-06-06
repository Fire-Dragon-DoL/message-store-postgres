CREATE OR REPLACE FUNCTION get_stream_messages(
  -- stream_name varchar,

  _position bigint DEFAULT 0,
  _batch_size bigint DEFAULT 1000,
  _condition varchar DEFAULT NULL
)
RETURNS SETOF message
AS $$
DECLARE
  command text;
BEGIN
  command := '
    SELECT
      id::varchar,
      stream_name::varchar,
      position::bigint,
      type::varchar,
      global_position::bigint,
      data::varchar,
      metadata::varchar,
      time::timestamp
    FROM
      messages
    WHERE
      position >= $1';

  if _condition is not null then
    command := command || ' AND
      %s';
    command := format(command, _condition);
  end if;

  command := command || '
    ORDER BY
      position ASC
    LIMIT
      $2';

  RAISE NOTICE '%', command;

  RETURN QUERY EXECUTE command USING _position, _batch_size;
END;
$$ LANGUAGE plpgsql
VOLATILE;
