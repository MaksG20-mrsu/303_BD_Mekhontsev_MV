#!/usr/bin/env python3
"""Генерирует SQL-скрипт db_init.sql для создания и наполнения базы movies_rating.db.

Исходные файлы (movies.csv, ratings.csv, tags.csv, users.txt) читаются из
каталога, где лежит этот скрипт. Результат (db_init.sql) записывается в
текущий каталог, откуда запускается скрипт.
"""
import csv
import os
import re

SRC_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_FILE = "db_init.sql"

YEAR_RE = re.compile(r"^(.*?)\s*\((\d{4})\)\s*$")


def q(value):
    """Строковый литерал SQL: одинарные кавычки внутри удваиваются."""
    return "'" + value.replace("'", "''") + "'"


def read_csv(name):
    with open(os.path.join(SRC_DIR, name), encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)  # пропускаем строку заголовка
        yield from reader


def read_users(name):
    with open(os.path.join(SRC_DIR, name), encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if line:
                yield line.split("|")


SCHEMA = """\
DROP TABLE IF EXISTS movies;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS users;

CREATE TABLE movies (
    id INTEGER PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    year INTEGER,
    genres VARCHAR(255)
);

CREATE TABLE ratings (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    movie_id INTEGER NOT NULL,
    rating REAL NOT NULL,
    timestamp INTEGER NOT NULL
);

CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    movie_id INTEGER NOT NULL,
    tag VARCHAR(255) NOT NULL,
    timestamp INTEGER NOT NULL
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    gender VARCHAR(10),
    register_date VARCHAR(10),
    occupation VARCHAR(50)
);
"""


def main():
    lines = [SCHEMA, "BEGIN TRANSACTION;"]

    for movie_id, title, genres in read_csv("movies.csv"):
        m = YEAR_RE.match(title)
        if m:
            title, year = m.group(1), m.group(2)
        else:
            year = "NULL"  # у части фильмов года в названии нет
        lines.append(
            "INSERT INTO movies (id, title, year, genres) "
            f"VALUES ({int(movie_id)}, {q(title)}, {year}, {q(genres)});"
        )

    for i, (user_id, movie_id, rating, ts) in enumerate(read_csv("ratings.csv"), 1):
        lines.append(
            "INSERT INTO ratings (id, user_id, movie_id, rating, timestamp) "
            f"VALUES ({i}, {int(user_id)}, {int(movie_id)}, {float(rating)}, {int(ts)});"
        )

    for i, (user_id, movie_id, tag, ts) in enumerate(read_csv("tags.csv"), 1):
        lines.append(
            "INSERT INTO tags (id, user_id, movie_id, tag, timestamp) "
            f"VALUES ({i}, {int(user_id)}, {int(movie_id)}, {q(tag)}, {int(ts)});"
        )

    for user_id, name, email, gender, reg_date, occupation in read_users("users.txt"):
        lines.append(
            "INSERT INTO users (id, name, email, gender, register_date, occupation) "
            f"VALUES ({int(user_id)}, {q(name)}, {q(email)}, {q(gender)}, "
            f"{q(reg_date)}, {q(occupation)});"
        )

    lines.append("COMMIT;")

    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Создан файл {OUT_FILE}")


if __name__ == "__main__":
    main()
