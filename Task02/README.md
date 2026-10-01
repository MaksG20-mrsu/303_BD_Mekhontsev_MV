# Task02. Скрипты для создания таблиц и загрузки данных

Утилита выполняет ETL: читает исходные файлы (`movies.csv`, `ratings.csv`, `tags.csv`, `users.txt`),
генерирует SQL-скрипт `db_init.sql` и загружает его в базу SQLite `movies_rating.db`.

## Требования к окружению

- Python 3 (используется только стандартная библиотека)
- SQLite (консольная утилита `sqlite3` должна быть доступна в `PATH`)
- Оболочка bash: в Linux и macOS есть по умолчанию, в Windows подойдёт Git Bash (устанавливается вместе с Git)

## Состав каталога

- `make_db_init.py` — утилита, формирующая `db_init.sql`
- `db_init.bat` — shell-скрипт запуска (шебанг `#!/bin/bash`)
- `movies.csv`, `ratings.csv`, `tags.csv`, `users.txt` — исходные данные

## Запуск

Из каталога `Task02`:

```bash
./db_init.bat
```

Если файл не исполняемый (или в Windows): `bash db_init.bat`.

Скрипт выполняет два действия:

1. `python3 make_db_init.py` — создаёт `db_init.sql`;
2. `sqlite3 movies_rating.db < db_init.sql` — загружает его в базу.

В результате создаётся заполненная база данных `movies_rating.db`. Если таблицы в ней уже
были, они удаляются и создаются заново.

## Структура базы данных

| Таблица | Поля |
|---------|------|
| `movies` | `id` (PK), `title`, `year`, `genres` |
| `ratings` | `id` (PK), `user_id`, `movie_id`, `rating`, `timestamp` |
| `tags` | `id` (PK), `user_id`, `movie_id`, `tag`, `timestamp` |
| `users` | `id` (PK), `name`, `email`, `gender`, `register_date`, `occupation` |

Особенности преобразования данных:

- год выпуска отделяется от названия фильма («Toy Story (1995)» → `title` = «Toy Story», `year` = 1995);
  если года в названии нет, в `year` записывается `NULL`;
- для `ratings` и `tags` значение `id` присваивается по порядку строк в исходном файле.
