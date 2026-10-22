create table if not exists analytics_events (
  id integer primary key autoincrement,
  occurred_at text not null,
  event_name text not null,
  path text,
  asset text,
  referrer text,
  session_id text,
  metadata text not null default '{}'
);

create index if not exists analytics_events_occurred_at_idx
  on analytics_events (occurred_at desc);

create index if not exists analytics_events_event_name_idx
  on analytics_events (event_name);

create table if not exists feedback_messages (
  id integer primary key autoincrement,
  created_at text not null,
  category text not null,
  message text not null,
  email text,
  app_version text,
  build_number text,
  os_version text,
  diagnostics text not null default '{}',
  user_agent text,
  session_id text
);

create index if not exists feedback_messages_created_at_idx
  on feedback_messages (created_at desc);

create index if not exists feedback_messages_category_idx
  on feedback_messages (category);
