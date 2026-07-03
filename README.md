# discourse-logout-schedule

Минимальный server-only плагин Discourse для планового сброса пользовательских сессий.

Плагин не занимается OIDC/Keycloak-авторизацией. Его задача - регулярно удалять Discourse `UserAuthToken` у всех не исключенных пользователей, чтобы следующий заход на форум прошел через OpenID Connect и Discourse получил свежие claims и группы из Keycloak.

## Настройки

В админке Discourse, в Site Settings:

- `discourse_logout_schedule_enabled` - включает job. По умолчанию `false`.
- `discourse_logout_schedule_day_of_week` - день недели. По умолчанию `sunday`.
- `discourse_logout_schedule_time` - локальное время запуска в формате `HH:MM`. По умолчанию `03:00`.
- `discourse_logout_schedule_timezone` - timezone для расписания. По умолчанию `Asia/Krasnoyarsk`.
- `discourse_logout_schedule_dry_run` - режим проверки без удаления токенов. По умолчанию `true`.
- `discourse_logout_schedule_excluded_usernames` - исключенные пользователи.
- `discourse_logout_schedule_excluded_groups` - исключенные группы. По умолчанию `admins|staff`.
- `discourse_logout_schedule_log_result` - писать результат в Rails logger. По умолчанию `true`.

Администраторы всегда исключаются дополнительно, даже если настройку групп поменяли.

## Установка

В `/var/discourse/containers/app.yml` добавь плагин в `hooks.after_code`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone <repo-url> discourse-logout-schedule
```

Затем rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

## Проверка через Rails console

Зайди в контейнер:

```bash
cd /var/discourse
./launcher enter app
rails c
```

Включи dry-run и запусти job вручную:

```ruby
SiteSetting.discourse_logout_schedule_enabled = true
SiteSetting.discourse_logout_schedule_dry_run = true
Jobs::DiscourseLogoutSchedule.new.execute(force: true)
```

Ручной запуск с `force: true` обходит расписание, но не записывает weekly run marker. Он нужен именно для проверки.

## Проверка логов

```bash
./launcher logs app | grep discourse-logout-schedule
```

В dry-run ожидай строку примерно такого вида:

```text
[discourse-logout-schedule] status=ok dry_run=true run_key="..." tokens_matched=12 affected_users=8 tokens_deleted=0 excluded_groups=["admins", "staff"] excluded_users=[[1, "admin"]]
```

В боевом режиме `tokens_deleted` должен совпасть с количеством удаленных `UserAuthToken`.

## Как работает расписание

Discourse scheduled job просыпается каждые 5 минут. Плагин сам проверяет configured weekday, local time и timezone. Когда окно наступило, он выполняет сброс и записывает marker в `PluginStore`, чтобы в этот же день не удалить токены повторно на следующем Sidekiq tick.

Для защиты от двойного запуска в нескольких Sidekiq-процессах используется `DistributedMutex`.

## Проверки разработки

Из standalone checkout можно проверить синтаксис:

```bash
ruby -c plugin.rb
ruby -c app/jobs/scheduled/discourse_logout_schedule.rb
ruby -c lib/discourse_logout_schedule/session_reset.rb
ruby -e "require 'yaml'; YAML.load_file('config/settings.yml')"
```

Полные RSpec-сценарии нужно запускать внутри Discourse dev checkout:

- disabled plugin no-ops;
- not-due schedule no-ops;
- due dry-run не удаляет токены;
- due real run удаляет токены не исключенных пользователей;
- admin/staff/group/user exclusions сохраняются;
- повторный запуск в том же schedule window no-ops;
- invalid time/timezone логирует предупреждение и no-ops.
