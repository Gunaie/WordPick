-- CloudBase（PostgreSQL 模式）同步表结构
-- 环境：splendid-cephalopod-xxxxxxxx
-- 用法：云开发控制台 → 数据库 → SQL 编辑器，整段粘贴执行
--
-- 设计说明：
--   * 所有表用 user_id 做隔离，单用户默认 'me'，后续可换成自定义同步码
--   * 时间统一用 timestamptz，客户端按 ISO8601 传值
--   * note 用软删除（deleted），保证跨端删除也能同步
--   * 主键均可在客户端生成，避免多端自增冲突

-- ── 1. 学习进度（SM-2 状态）─────────────────────────────
create table if not exists review_state (
  user_id     text             not null default 'me',
  word_key    text             not null,
  ease        double precision not null default 2.5,
  interval    integer          not null default 0,
  reps        integer          not null default 0,
  lapses      integer          not null default 0,
  due         timestamptz      not null default now(),
  updated_at  timestamptz      not null default now(),
  primary key (user_id, word_key)
);

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

-- 已建过旧表的库执行下面两句补列（v0.10 起笔记支持标题与标签）
-- alter table note add column if not exists title text not null default '';
-- alter table note add column if not exists tags text[] not null default '{}';

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

-- ── 验证 ───────────────────────────────────────────────
-- 执行后应能看到三张表
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
