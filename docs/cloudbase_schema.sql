-- CloudBase（PostgreSQL 模式）同步表结构（BYOC：每个用户在自己的环境里执行）
-- 用法：云开发控制台 → 选你自己的环境 → 数据库 → SQL 编辑器，整段粘贴执行
--
-- 设计说明：
--   * 隔离边界是「环境」：每人用自己的环境，互不可见，是推荐用法。
--   * 同环境内用 user_id 区分（主要用于同一人多台设备互通）；若要把一个环境
--     共享给多人，务必启用文末的 RLS，并改成需要登录鉴权的部署，否则 user_id
--     可被客户端伪造，无法保证隔离。
--   * 时间统一用 timestamptz，客户端按 ISO8601 传值
--   * note 用软删除（deleted），保证跨端删除也能同步
--   * 主键均可在客户端生成，避免多端自增冲突

-- ── 1. 学习进度（FSRS-6 默认，SM-2 字段保留用于回滚）──────
create table if not exists review_state (
  user_id     text             not null default 'me',
  word_key    text             not null,
  ease        double precision not null default 2.5,
  interval    integer          not null default 0,
  reps        integer          not null default 0,
  lapses      integer          not null default 0,
  due         timestamptz      not null default now(),
  updated_at  timestamptz      not null default now(),
  stability   double precision,
  difficulty  double precision,
  fsrs_state  text,
  fsrs_step   integer,
  last_review timestamptz,
  primary key (user_id, word_key)
);

-- 已建过旧表的库：下面 5 句必须执行（幂等，可重复运行）。
-- v0.22 起默认 FSRS-6，评分会写入这些字段；缺列会导致同步报 42703，见 ISSUE-035。
alter table review_state add column if not exists stability double precision;
alter table review_state add column if not exists difficulty double precision;
alter table review_state add column if not exists fsrs_state text;
alter table review_state add column if not exists fsrs_step integer;
alter table review_state add column if not exists last_review timestamptz;

create index if not exists review_state_due_idx
  on review_state (user_id, due);

-- ── 2. 笔记 ────────────────────────────────────────────
create table if not exists note (
  id          text        primary key,
  user_id     text        not null default 'me',
  word_key    text        not null,
  title       text        not null default '',
  content     text        not null,
  tags        text[]      not null default '{}',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted     boolean     not null default false
);

-- 已建过旧表的库：下面 2 句必须执行（幂等，可重复运行）。
-- v0.10 起笔记支持标题与标签；缺列会导致 note 同步报 42703，见 ISSUE-033。
alter table note add column if not exists title text not null default '';
alter table note add column if not exists tags text[] not null default '{}';

create index if not exists note_user_idx
  on note (user_id, created_at desc);

-- ── 3. 键值数据（自建词、设置）───────────────────────────
create table if not exists user_meta (
  user_id     text        not null default 'me',
  key         text        not null,
  value       text        not null,
  updated_at  timestamptz not null default now(),
  primary key (user_id, key)
);

-- ── 4. 授权给 anon（客户端使用的 Publishable Key 角色）────
-- 说明：建表后默认只有读权限，客户端写入会报
--       DATABASE_42501 permission denied for table
grant usage on schema public to anon;
grant select, insert, update, delete
  on table review_state, note, user_meta to anon;

-- ── 可选：共享环境下的行级安全（RLS）────────────────────
-- 默认不开。仅当你把同一个环境共享给多人时才需要；单用户 / 每人独立环境可忽略。
-- 前提：客户端必须以已登录身份访问，且网关把用户标识注入 PostgREST 的 GUC
--      `app.user_id`（匿名 anon Key 无法区分用户，开了 RLS 会让客户端读不到数据）。
-- alter table review_state enable row level security;
-- alter table note          enable row level security;
-- alter table user_meta     enable row level security;
-- create policy review_state_owner on review_state
--   using (user_id = current_setting('app.user_id', true))
--   with check (user_id = current_setting('app.user_id', true));
-- create policy note_owner on note
--   using (user_id = current_setting('app.user_id', true))
--   with check (user_id = current_setting('app.user_id', true));
-- create policy user_meta_owner on user_meta
--   using (user_id = current_setting('app.user_id', true))
--   with check (user_id = current_setting('app.user_id', true));

-- ── 验证 ───────────────────────────────────────────────
-- 执行后应能看到三张表
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
