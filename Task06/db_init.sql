-- Лабораторная работа 6. База данных для автоматизации станции технического
-- обслуживания (СТО). СУБД: SQLite.
-- Запуск: sqlite3 sto.db ".read db_init.sql"
--
-- Модель:
--   masters              - мастера (кадровый учёт, индивидуальный процент от выручки);
--                          уволенные мастера остаются в базе (dismissal_date), удалять нельзя
--   schedules            - индивидуальный график работы мастера по дням
--   services             - справочник услуг (название, длительность, цена)
--   clients, cars        - клиенты и их автомобили
--   appointments         - предварительные записи к мастеру
--   appointment_services - услуги, выбранные в записи (связь «многие ко многим»)
--   performed_works      - фактически выполненные работы (основа расчёта зарплаты)

-- Проверка внешних ключей в SQLite включается отдельно для каждого соединения.
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS performed_works;
DROP TABLE IF EXISTS appointment_services;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS schedules;
DROP TABLE IF EXISTS cars;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS masters;

-- Мастера. Вместо удаления при увольнении заполняется dismissal_date:
-- NULL - работает, иначе - последний рабочий день.
CREATE TABLE masters (
    id             INTEGER PRIMARY KEY,
    last_name      VARCHAR(50)   NOT NULL,
    first_name     VARCHAR(50)   NOT NULL,
    middle_name    VARCHAR(50),
    phone          VARCHAR(20)   NOT NULL UNIQUE,
    hire_date      DATE          NOT NULL CHECK (date(hire_date) IS hire_date),
    dismissal_date DATE          CHECK (dismissal_date IS NULL OR
                                        (date(dismissal_date) IS dismissal_date AND dismissal_date >= hire_date)),
    salary_percent DECIMAL(5, 2) NOT NULL DEFAULT 30
                                 CHECK (salary_percent >= 0 AND salary_percent <= 100)
);

-- Индивидуальный график: одна рабочая смена мастера в конкретный день.
CREATE TABLE schedules (
    master_id  INTEGER    NOT NULL REFERENCES masters (id) ON DELETE RESTRICT,
    work_date  DATE       NOT NULL CHECK (date(work_date) IS work_date),
    start_time VARCHAR(5) NOT NULL CHECK (strftime('%H:%M', start_time) IS start_time),
    end_time   VARCHAR(5) NOT NULL CHECK (strftime('%H:%M', end_time) IS end_time),
    PRIMARY KEY (master_id, work_date),
    CHECK (end_time > start_time)
);

-- Справочник услуг. Услуги, которые больше не оказываются, помечаются is_active = 0
-- (удалить их нельзя, пока на них есть ссылки).
CREATE TABLE services (
    id           INTEGER PRIMARY KEY,
    name         VARCHAR(100)  NOT NULL UNIQUE,
    duration_min INTEGER       NOT NULL CHECK (duration_min > 0),
    price        DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    is_active    INTEGER       NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE clients (
    id         INTEGER PRIMARY KEY,
    last_name  VARCHAR(50)  NOT NULL,
    first_name VARCHAR(50)  NOT NULL,
    phone      VARCHAR(20)  NOT NULL UNIQUE,
    email      VARCHAR(100) CHECK (email IS NULL OR email LIKE '%_@_%')
);

CREATE TABLE cars (
    id            INTEGER PRIMARY KEY,
    client_id     INTEGER     NOT NULL REFERENCES clients (id) ON DELETE RESTRICT,
    license_plate VARCHAR(12) NOT NULL UNIQUE,
    brand         VARCHAR(50) NOT NULL,
    model         VARCHAR(50) NOT NULL,
    year          INTEGER     CHECK (year IS NULL OR year BETWEEN 1950 AND 2100)
);

-- Предварительная запись к мастеру. Клиент определяется через автомобиль.
-- Время окончания (end_at) = начало + суммарная длительность выбранных услуг.
-- Статусы: booked - записан, completed - выполнена, cancelled - отменена, no_show - клиент не пришёл.
CREATE TABLE appointments (
    id         INTEGER PRIMARY KEY,
    car_id     INTEGER      NOT NULL REFERENCES cars (id)    ON DELETE RESTRICT,
    master_id  INTEGER      NOT NULL REFERENCES masters (id) ON DELETE RESTRICT,
    start_at   DATETIME     NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', start_at) IS start_at),
    end_at     DATETIME     NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', end_at) IS end_at),
    status     VARCHAR(12)  NOT NULL DEFAULT 'booked'
                            CHECK (status IN ('booked', 'completed', 'cancelled', 'no_show')),
    created_at DATETIME     NOT NULL DEFAULT (datetime('now')),
    comment    VARCHAR(255),
    CHECK (end_at > start_at),
    CHECK (date(end_at) = date(start_at))
);

-- Услуги, выбранные при записи. При удалении записи они удаляются вместе с ней.
CREATE TABLE appointment_services (
    appointment_id INTEGER NOT NULL REFERENCES appointments (id) ON DELETE CASCADE,
    service_id     INTEGER NOT NULL REFERENCES services (id)     ON DELETE RESTRICT,
    PRIMARY KEY (appointment_id, service_id)
);

-- Фактически выполненные работы. master_id - тот, кто реально выполнил работу
-- (может отличаться от записанного, например при замене), price - фактическая
-- стоимость (цена в справочнике со временем меняется).
CREATE TABLE performed_works (
    id             INTEGER PRIMARY KEY,
    appointment_id INTEGER       NOT NULL REFERENCES appointments (id) ON DELETE RESTRICT,
    service_id     INTEGER       NOT NULL REFERENCES services (id)     ON DELETE RESTRICT,
    master_id      INTEGER       NOT NULL REFERENCES masters (id)      ON DELETE RESTRICT,
    performed_at   DATETIME      NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', performed_at) IS performed_at),
    price          DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    UNIQUE (appointment_id, service_id)
);

-- Индексы для частых запросов (занятость мастера, отчёты, расчёт зарплаты, внешние ключи).
CREATE INDEX idx_masters_last_name            ON masters (last_name);
CREATE INDEX idx_clients_last_name            ON clients (last_name);
CREATE INDEX idx_cars_client_id               ON cars (client_id);
CREATE INDEX idx_appointments_master_start    ON appointments (master_id, start_at);
CREATE INDEX idx_appointments_car_id          ON appointments (car_id);
CREATE INDEX idx_appointment_services_service ON appointment_services (service_id);
CREATE INDEX idx_performed_works_master_date  ON performed_works (master_id, performed_at);
CREATE INDEX idx_performed_works_service      ON performed_works (service_id);

-- Мастеров удалять нельзя: данные о их работе должны сохраняться.
-- Вместо удаления нужно указать дату увольнения (dismissal_date).
CREATE TRIGGER trg_masters_no_delete
BEFORE DELETE ON masters
BEGIN
    SELECT RAISE(ABORT, 'Мастера нельзя удалять: укажите дату увольнения (dismissal_date)');
END;

-- Контроль записи с учётом занятости мастера (при добавлении записи).
CREATE TRIGGER trg_appointments_check_insert
BEFORE INSERT ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Неверный формат времени записи (нужно ГГГГ-ММ-ДД ЧЧ:ММ)')
    WHERE strftime('%Y-%m-%d %H:%M', NEW.start_at) IS NOT NEW.start_at
       OR strftime('%Y-%m-%d %H:%M', NEW.end_at)   IS NOT NEW.end_at;
    SELECT RAISE(ABORT, 'Мастер не работает в станции на дату записи (не принят или уволен)')
    WHERE NOT EXISTS (SELECT 1 FROM masters m
                      WHERE m.id = NEW.master_id
                        AND m.hire_date <= date(NEW.start_at)
                        AND (m.dismissal_date IS NULL OR m.dismissal_date >= date(NEW.start_at)));
    SELECT RAISE(ABORT, 'Запись выходит за рамки рабочего графика мастера')
    WHERE NOT EXISTS (SELECT 1 FROM schedules s
                      WHERE s.master_id = NEW.master_id
                        AND s.work_date = date(NEW.start_at)
                        AND s.start_time <= strftime('%H:%M', NEW.start_at)
                        AND s.end_time   >= strftime('%H:%M', NEW.end_at));
    SELECT RAISE(ABORT, 'Мастер занят в это время')
    WHERE EXISTS (SELECT 1 FROM appointments a
                  WHERE a.master_id = NEW.master_id
                    AND a.status <> 'cancelled'
                    AND a.start_at < NEW.end_at
                    AND a.end_at   > NEW.start_at);
END;

-- То же при изменении мастера, времени или статуса записи.
CREATE TRIGGER trg_appointments_check_update
BEFORE UPDATE OF master_id, start_at, end_at, status ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Неверный формат времени записи (нужно ГГГГ-ММ-ДД ЧЧ:ММ)')
    WHERE strftime('%Y-%m-%d %H:%M', NEW.start_at) IS NOT NEW.start_at
       OR strftime('%Y-%m-%d %H:%M', NEW.end_at)   IS NOT NEW.end_at;
    SELECT RAISE(ABORT, 'Мастер не работает в станции на дату записи (не принят или уволен)')
    WHERE NOT EXISTS (SELECT 1 FROM masters m
                      WHERE m.id = NEW.master_id
                        AND m.hire_date <= date(NEW.start_at)
                        AND (m.dismissal_date IS NULL OR m.dismissal_date >= date(NEW.start_at)));
    SELECT RAISE(ABORT, 'Запись выходит за рамки рабочего графика мастера')
    WHERE NOT EXISTS (SELECT 1 FROM schedules s
                      WHERE s.master_id = NEW.master_id
                        AND s.work_date = date(NEW.start_at)
                        AND s.start_time <= strftime('%H:%M', NEW.start_at)
                        AND s.end_time   >= strftime('%H:%M', NEW.end_at));
    SELECT RAISE(ABORT, 'Мастер занят в это время')
    WHERE EXISTS (SELECT 1 FROM appointments a
                  WHERE a.id <> NEW.id
                    AND a.master_id = NEW.master_id
                    AND a.status <> 'cancelled'
                    AND a.start_at < NEW.end_at
                    AND a.end_at   > NEW.start_at);
END;

-- ---------------------------------------------------------------------------
-- Тестовые данные
-- ---------------------------------------------------------------------------

BEGIN TRANSACTION;

-- Мастера (мастер 5 уволен, но его данные остаются в базе)
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (1, 'Иванов', 'Пётр', 'Сергеевич', '+7 927 100-20-01', '2019-03-11', NULL, 40);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (2, 'Смирнова', 'Елена', 'Андреевна', '+7 927 100-20-02', '2021-06-01', NULL, 35);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (3, 'Кузнецов', 'Алексей', 'Викторович', '+7 927 100-20-03', '2022-09-15', NULL, 38.5);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (4, 'Попов', 'Дмитрий', 'Олегович', '+7 927 100-20-04', '2024-02-05', NULL, 30);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (5, 'Васильев', 'Игорь', 'Николаевич', '+7 927 100-20-05', '2018-05-20', '2026-09-30', 42);

-- Справочник услуг
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (1, 'Замена масла и масляного фильтра', 40, 1500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (2, 'Диагностика ходовой части', 30, 800, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (3, 'Компьютерная диагностика двигателя', 45, 1200, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (4, 'Замена тормозных колодок (одна ось)', 60, 2500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (5, 'Замена воздушного фильтра', 20, 600, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (6, 'Шиномонтаж (4 колеса)', 60, 2000, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (7, 'Балансировка колёс (4 колеса)', 40, 1600, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (8, 'Замена ремня ГРМ', 180, 7500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (9, 'Замена свечей зажигания', 30, 1000, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (10, 'Регулировка развал-схождения', 60, 2800, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (11, 'Антикоррозийная обработка кузова', 120, 5000, 0);

-- Клиенты
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (1, 'Орлов', 'Андрей', '+7 937 200-30-01', 'orlov.a@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (2, 'Фёдорова', 'Мария', '+7 937 200-30-02', 'fedorova.m@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (3, 'Григорьев', 'Сергей', '+7 937 200-30-03', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (4, 'Николаева', 'Ольга', '+7 937 200-30-04', 'nikolaeva.o@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (5, 'Захаров', 'Виктор', '+7 937 200-30-05', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (6, 'Макарова', 'Анна', '+7 937 200-30-06', 'makarova.a@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (7, 'Борисов', 'Роман', '+7 937 200-30-07', 'borisov.r@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (8, 'Тихонова', 'Дарья', '+7 937 200-30-08', NULL);

-- Автомобили
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (1, 1, 'А123ВС13', 'Lada', 'Vesta', 2019);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (2, 1, 'К456ОР13', 'Lada', 'Granta', 2016);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (3, 2, 'М789ТХ13', 'Kia', 'Rio', 2020);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (4, 3, 'Н321АЕ13', 'Hyundai', 'Solaris', 2018);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (5, 4, 'О654КМ13', 'Toyota', 'Camry', 2021);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (6, 5, 'Р987НУ13', 'Renault', 'Logan', 2015);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (7, 6, 'С147ХВ13', 'Skoda', 'Octavia', 2017);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (8, 6, 'Т258РА13', 'Volkswagen', 'Polo', 2022);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (9, 7, 'У369ОЕ13', 'Ford', 'Focus', 2014);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (10, 8, 'Х741МС13', 'Nissan', 'Qashqai', 2019);

-- Графики работы мастеров (у каждого свой график)
-- мастер 1 (Иванов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (1, '2026-10-19', '09:00', '18:00'),
    (1, '2026-10-20', '09:00', '18:00'),
    (1, '2026-10-21', '09:00', '18:00'),
    (1, '2026-10-22', '09:00', '18:00'),
    (1, '2026-10-23', '09:00', '18:00'),
    (1, '2026-10-26', '09:00', '18:00'),
    (1, '2026-10-27', '09:00', '18:00'),
    (1, '2026-10-28', '09:00', '18:00'),
    (1, '2026-10-29', '09:00', '18:00'),
    (1, '2026-10-30', '09:00', '18:00'),
    (1, '2026-11-02', '09:00', '18:00'),
    (1, '2026-11-03', '09:00', '18:00'),
    (1, '2026-11-04', '09:00', '18:00'),
    (1, '2026-11-05', '09:00', '18:00'),
    (1, '2026-11-06', '09:00', '18:00'),
    (1, '2026-11-09', '09:00', '18:00'),
    (1, '2026-11-10', '09:00', '18:00'),
    (1, '2026-11-11', '09:00', '18:00'),
    (1, '2026-11-12', '09:00', '18:00'),
    (1, '2026-11-13', '09:00', '18:00'),
    (1, '2026-11-30', '09:00', '18:00'),
    (1, '2026-12-01', '09:00', '18:00'),
    (1, '2026-12-02', '09:00', '18:00'),
    (1, '2026-12-03', '09:00', '18:00'),
    (1, '2026-12-04', '09:00', '18:00'),
    (1, '2026-12-07', '09:00', '18:00'),
    (1, '2026-12-08', '09:00', '18:00'),
    (1, '2026-12-09', '09:00', '18:00'),
    (1, '2026-12-10', '09:00', '18:00'),
    (1, '2026-12-11', '09:00', '18:00');
-- мастер 2 (Смирнова)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (2, '2026-10-20', '10:00', '19:00'),
    (2, '2026-10-21', '10:00', '19:00'),
    (2, '2026-10-22', '10:00', '19:00'),
    (2, '2026-10-23', '10:00', '19:00'),
    (2, '2026-10-24', '10:00', '19:00'),
    (2, '2026-10-27', '10:00', '19:00'),
    (2, '2026-10-28', '10:00', '19:00'),
    (2, '2026-10-29', '10:00', '19:00'),
    (2, '2026-10-30', '10:00', '19:00'),
    (2, '2026-10-31', '10:00', '19:00'),
    (2, '2026-11-03', '10:00', '19:00'),
    (2, '2026-11-04', '10:00', '19:00'),
    (2, '2026-11-05', '10:00', '19:00'),
    (2, '2026-11-06', '10:00', '19:00'),
    (2, '2026-11-07', '10:00', '19:00'),
    (2, '2026-11-10', '10:00', '19:00'),
    (2, '2026-11-11', '10:00', '19:00'),
    (2, '2026-11-12', '10:00', '19:00'),
    (2, '2026-11-13', '10:00', '19:00'),
    (2, '2026-12-01', '10:00', '19:00'),
    (2, '2026-12-02', '10:00', '19:00'),
    (2, '2026-12-03', '10:00', '19:00'),
    (2, '2026-12-04', '10:00', '19:00'),
    (2, '2026-12-05', '10:00', '19:00'),
    (2, '2026-12-08', '10:00', '19:00'),
    (2, '2026-12-09', '10:00', '19:00'),
    (2, '2026-12-10', '10:00', '19:00'),
    (2, '2026-12-11', '10:00', '19:00');
-- мастер 3 (Кузнецов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (3, '2026-10-19', '08:00', '17:00'),
    (3, '2026-10-20', '08:00', '17:00'),
    (3, '2026-10-22', '08:00', '17:00'),
    (3, '2026-10-23', '08:00', '17:00'),
    (3, '2026-10-26', '08:00', '17:00'),
    (3, '2026-10-27', '08:00', '17:00'),
    (3, '2026-10-29', '08:00', '17:00'),
    (3, '2026-10-30', '08:00', '17:00'),
    (3, '2026-11-02', '08:00', '17:00'),
    (3, '2026-11-03', '08:00', '17:00'),
    (3, '2026-11-05', '08:00', '17:00'),
    (3, '2026-11-06', '08:00', '17:00'),
    (3, '2026-11-09', '08:00', '17:00'),
    (3, '2026-11-10', '08:00', '17:00'),
    (3, '2026-11-12', '08:00', '17:00'),
    (3, '2026-11-13', '08:00', '17:00'),
    (3, '2026-11-30', '08:00', '17:00'),
    (3, '2026-12-01', '08:00', '17:00'),
    (3, '2026-12-03', '08:00', '17:00'),
    (3, '2026-12-04', '08:00', '17:00'),
    (3, '2026-12-07', '08:00', '17:00'),
    (3, '2026-12-08', '08:00', '17:00'),
    (3, '2026-12-10', '08:00', '17:00'),
    (3, '2026-12-11', '08:00', '17:00');
-- мастер 4 (Попов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (4, '2026-10-19', '09:00', '17:00'),
    (4, '2026-10-21', '09:00', '17:00'),
    (4, '2026-10-23', '09:00', '17:00'),
    (4, '2026-10-24', '10:00', '15:00'),
    (4, '2026-10-26', '09:00', '17:00'),
    (4, '2026-10-28', '09:00', '17:00'),
    (4, '2026-10-30', '09:00', '17:00'),
    (4, '2026-10-31', '10:00', '15:00'),
    (4, '2026-11-02', '09:00', '17:00'),
    (4, '2026-11-04', '09:00', '17:00'),
    (4, '2026-11-06', '09:00', '17:00'),
    (4, '2026-11-07', '10:00', '15:00'),
    (4, '2026-11-09', '09:00', '17:00'),
    (4, '2026-11-11', '09:00', '17:00'),
    (4, '2026-11-13', '09:00', '17:00'),
    (4, '2026-11-30', '09:00', '17:00'),
    (4, '2026-12-02', '09:00', '17:00'),
    (4, '2026-12-04', '09:00', '17:00'),
    (4, '2026-12-05', '10:00', '15:00'),
    (4, '2026-12-07', '09:00', '17:00'),
    (4, '2026-12-09', '09:00', '17:00'),
    (4, '2026-12-11', '09:00', '17:00');
-- мастер 5 (Васильев)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (5, '2026-09-07', '09:00', '18:00'),
    (5, '2026-09-08', '09:00', '18:00'),
    (5, '2026-09-09', '09:00', '18:00'),
    (5, '2026-09-10', '09:00', '18:00'),
    (5, '2026-09-11', '09:00', '18:00'),
    (5, '2026-09-14', '09:00', '18:00'),
    (5, '2026-09-15', '09:00', '18:00'),
    (5, '2026-09-16', '09:00', '18:00'),
    (5, '2026-09-17', '09:00', '18:00'),
    (5, '2026-09-18', '09:00', '18:00'),
    (5, '2026-09-21', '09:00', '18:00'),
    (5, '2026-09-22', '09:00', '18:00'),
    (5, '2026-09-23', '09:00', '18:00'),
    (5, '2026-09-24', '09:00', '18:00'),
    (5, '2026-09-25', '09:00', '18:00'),
    (5, '2026-09-28', '09:00', '18:00'),
    (5, '2026-09-29', '09:00', '18:00'),
    (5, '2026-09-30', '09:00', '18:00');

-- Предварительные записи (триггеры проверяют график и занятость мастера)
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (1, 2, 1, '2026-10-19 10:00', '2026-10-19 13:00', 'cancelled', '2026-10-14 05:15:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (2, 10, 1, '2026-10-19 14:00', '2026-10-19 15:30', 'completed', '2026-10-18 10:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (3, 6, 1, '2026-10-27 09:30', '2026-10-27 11:15', 'completed', '2026-10-21 05:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (4, 9, 1, '2026-10-27 11:15', '2026-10-27 12:55', 'completed', '2026-10-23 09:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (5, 10, 1, '2026-10-28 09:00', '2026-10-28 10:30', 'completed', '2026-10-27 05:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (6, 7, 1, '2026-10-28 11:00', '2026-10-28 12:15', 'completed', '2026-10-24 07:00:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (7, 8, 1, '2026-11-09 09:00', '2026-11-09 12:00', 'completed', '2026-11-03 04:30:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (8, 8, 1, '2026-11-11 10:00', '2026-11-11 11:00', 'completed', '2026-11-07 06:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (9, 1, 1, '2026-11-11 11:30', '2026-11-11 12:10', 'completed', '2026-11-06 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (10, 8, 1, '2026-11-12 09:30', '2026-11-12 11:10', 'completed', '2026-11-07 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (11, 2, 1, '2026-11-12 11:40', '2026-11-12 12:40', 'completed', '2026-11-06 07:10:00', 'Просит позвонить за час до приезда');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (12, 2, 1, '2026-12-02 09:30', '2026-12-02 10:30', 'booked', '2026-11-30 03:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (13, 2, 1, '2026-12-04 10:00', '2026-12-04 11:40', 'booked', '2026-11-29 08:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (14, 10, 1, '2026-12-11 10:00', '2026-12-11 10:40', 'booked', '2026-12-07 04:45:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (15, 5, 2, '2026-10-21 11:00', '2026-10-21 12:40', 'completed', '2026-10-15 09:45:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (16, 7, 2, '2026-10-21 13:10', '2026-10-21 14:50', 'completed', '2026-10-19 08:55:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (17, 6, 2, '2026-10-23 10:00', '2026-10-23 11:15', 'completed', '2026-10-22 09:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (18, 7, 2, '2026-10-31 11:00', '2026-10-31 11:30', 'completed', '2026-10-27 06:45:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (19, 7, 2, '2026-10-31 11:30', '2026-10-31 13:10', 'completed', '2026-10-25 10:30:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (20, 1, 2, '2026-11-05 11:00', '2026-11-05 12:45', 'completed', '2026-10-31 09:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (21, 5, 2, '2026-11-05 13:15', '2026-11-05 14:45', 'completed', '2026-11-01 12:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (22, 7, 2, '2026-11-06 10:30', '2026-11-06 11:30', 'completed', '2026-11-04 07:45:00', 'Просит позвонить за час до приезда');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (23, 9, 2, '2026-11-06 11:30', '2026-11-06 13:10', 'completed', '2026-11-05 10:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (24, 9, 2, '2026-12-04 11:00', '2026-12-04 11:40', 'booked', '2026-12-02 10:30:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (25, 5, 2, '2026-12-04 12:10', '2026-12-04 12:50', 'booked', '2026-11-29 09:55:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (26, 1, 2, '2026-12-05 10:00', '2026-12-05 11:00', 'booked', '2026-12-02 04:45:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (27, 6, 2, '2026-12-09 10:30', '2026-12-09 12:15', 'booked', '2026-12-07 08:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (28, 5, 3, '2026-10-22 08:00', '2026-10-22 08:40', 'completed', '2026-10-16 03:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (29, 7, 3, '2026-10-30 09:00', '2026-10-30 10:00', 'no_show', '2026-10-29 03:30:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (30, 7, 3, '2026-11-02 08:00', '2026-11-02 09:00', 'cancelled', '2026-10-30 02:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (31, 7, 3, '2026-11-02 09:00', '2026-11-02 09:45', 'completed', '2026-11-01 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (32, 1, 3, '2026-11-05 08:00', '2026-11-05 09:00', 'completed', '2026-11-02 03:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (33, 3, 3, '2026-11-05 10:00', '2026-11-05 10:40', 'completed', '2026-11-01 06:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (34, 9, 3, '2026-11-09 09:00', '2026-11-09 10:00', 'completed', '2026-11-05 06:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (35, 5, 3, '2026-11-10 08:30', '2026-11-10 10:00', 'no_show', '2026-11-08 03:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (36, 9, 3, '2026-11-10 10:00', '2026-11-10 13:00', 'completed', '2026-11-07 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (37, 9, 3, '2026-11-13 08:00', '2026-11-13 11:00', 'cancelled', '2026-11-07 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (38, 8, 3, '2026-12-01 08:30', '2026-12-01 11:30', 'booked', '2026-11-26 05:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (39, 9, 3, '2026-12-04 08:30', '2026-12-04 09:45', 'booked', '2026-11-28 05:30:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (40, 5, 3, '2026-12-07 09:00', '2026-12-07 10:00', 'booked', '2026-12-05 04:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (41, 9, 4, '2026-10-19 09:30', '2026-10-19 11:10', 'completed', '2026-10-13 08:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (42, 7, 4, '2026-10-19 11:40', '2026-10-19 12:40', 'completed', '2026-10-16 09:40:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (43, 5, 4, '2026-10-21 09:30', '2026-10-21 11:10', 'completed', '2026-10-17 08:30:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (44, 6, 4, '2026-10-21 12:10', '2026-10-21 13:40', 'completed', '2026-10-16 11:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (45, 1, 4, '2026-10-24 11:00', '2026-10-24 14:00', 'cancelled', '2026-10-23 08:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (46, 2, 4, '2026-10-28 09:30', '2026-10-28 10:30', 'cancelled', '2026-10-22 08:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (47, 9, 4, '2026-10-31 10:00', '2026-10-31 11:40', 'completed', '2026-10-28 04:15:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (48, 2, 4, '2026-10-31 12:10', '2026-10-31 13:10', 'completed', '2026-10-30 08:40:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (49, 6, 4, '2026-11-02 10:00', '2026-11-02 11:40', 'completed', '2026-10-27 04:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (50, 4, 4, '2026-11-02 12:10', '2026-11-02 13:20', 'completed', '2026-10-31 06:40:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (51, 3, 4, '2026-11-07 11:00', '2026-11-07 11:40', 'completed', '2026-11-04 10:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (52, 3, 4, '2026-11-07 12:40', '2026-11-07 13:25', 'completed', '2026-11-04 11:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (53, 7, 4, '2026-11-09 09:30', '2026-11-09 12:30', 'completed', '2026-11-04 04:00:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (54, 2, 4, '2026-11-09 13:30', '2026-11-09 14:30', 'completed', '2026-11-05 08:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (55, 1, 4, '2026-11-13 10:00', '2026-11-13 11:10', 'completed', '2026-11-07 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (56, 8, 4, '2026-11-13 12:10', '2026-11-13 13:25', 'cancelled', '2026-11-09 10:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (57, 9, 5, '2026-09-08 10:00', '2026-09-08 10:30', 'completed', '2026-09-07 08:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (58, 10, 5, '2026-09-08 11:30', '2026-09-08 12:00', 'completed', '2026-09-02 09:30:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (59, 3, 5, '2026-09-14 09:30', '2026-09-14 10:10', 'completed', '2026-09-09 07:45:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (60, 6, 5, '2026-09-14 10:40', '2026-09-14 11:40', 'completed', '2026-09-10 07:55:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (61, 8, 5, '2026-09-15 09:00', '2026-09-15 09:40', 'completed', '2026-09-12 05:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (62, 7, 5, '2026-09-15 10:10', '2026-09-15 11:50', 'completed', '2026-09-10 09:25:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (63, 3, 5, '2026-09-25 10:00', '2026-09-25 11:15', 'completed', '2026-09-20 05:15:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (64, 9, 5, '2026-09-30 09:00', '2026-09-30 10:30', 'cancelled', '2026-09-28 04:45:00', NULL);

-- Услуги в записях
INSERT INTO appointment_services (appointment_id, service_id) VALUES
    (1, 8),
    (2, 10),
    (2, 2),
    (3, 1),
    (3, 3),
    (3, 5),
    (4, 6),
    (4, 7),
    (5, 4),
    (5, 2),
    (6, 9),
    (6, 3),
    (7, 8),
    (8, 10),
    (9, 1),
    (10, 6),
    (10, 7),
    (11, 6),
    (12, 4),
    (13, 6),
    (13, 7),
    (14, 7),
    (15, 6),
    (15, 7),
    (16, 6),
    (16, 7),
    (17, 9),
    (17, 3),
    (18, 2),
    (19, 6),
    (19, 7),
    (20, 1),
    (20, 3),
    (20, 5),
    (21, 4),
    (21, 2),
    (22, 6),
    (23, 6),
    (23, 7),
    (24, 7),
    (25, 7),
    (26, 1),
    (26, 5),
    (27, 1),
    (27, 3),
    (27, 5),
    (28, 1),
    (29, 6),
    (30, 10),
    (31, 3),
    (32, 1),
    (32, 5),
    (33, 7),
    (34, 10),
    (35, 4),
    (35, 2),
    (36, 8),
    (37, 8),
    (38, 8),
    (39, 9),
    (39, 3),
    (40, 10),
    (41, 6),
    (41, 7),
    (42, 10),
    (43, 6),
    (43, 7),
    (44, 4),
    (44, 2),
    (45, 8),
    (46, 6),
    (47, 6),
    (47, 7),
    (48, 1),
    (48, 5),
    (49, 6),
    (49, 7),
    (50, 1),
    (50, 9),
    (51, 7),
    (52, 3),
    (53, 8),
    (54, 4),
    (55, 1),
    (55, 9),
    (56, 9),
    (56, 3),
    (57, 2),
    (58, 2),
    (59, 1),
    (60, 4),
    (61, 1),
    (62, 6),
    (62, 7),
    (63, 9),
    (63, 3),
    (64, 4),
    (64, 2);

-- Фактически выполненные работы (цена - фактическая на момент выполнения)
INSERT INTO performed_works (id, appointment_id, service_id, master_id, performed_at, price) VALUES
    (1, 2, 10, 1, '2026-10-19 15:30', 2340.0),
    (2, 2, 2, 1, '2026-10-19 15:30', 800),
    (3, 3, 1, 1, '2026-10-27 11:15', 1500),
    (4, 3, 3, 1, '2026-10-27 11:15', 1200),
    (5, 3, 5, 1, '2026-10-27 11:15', 600),
    (6, 4, 6, 1, '2026-10-27 12:55', 2000),
    (7, 4, 7, 1, '2026-10-27 12:55', 1600),
    (8, 5, 4, 1, '2026-10-28 10:30', 2300),
    (9, 5, 2, 1, '2026-10-28 10:30', 800),
    (10, 6, 9, 1, '2026-10-28 12:15', 1000),
    (11, 6, 3, 1, '2026-10-28 12:15', 1200),
    (12, 7, 8, 1, '2026-11-09 12:00', 7500),
    (13, 8, 10, 1, '2026-11-11 11:00', 2800),
    (14, 9, 1, 1, '2026-11-11 12:10', 1500),
    (15, 10, 6, 1, '2026-11-12 11:10', 2000),
    (16, 10, 7, 1, '2026-11-12 11:10', 1600),
    (17, 11, 6, 1, '2026-11-12 12:40', 2000),
    (18, 15, 6, 2, '2026-10-21 12:40', 2000),
    (19, 15, 7, 2, '2026-10-21 12:40', 1600),
    (20, 16, 6, 2, '2026-10-21 14:50', 2000),
    (21, 16, 7, 2, '2026-10-21 14:50', 1600),
    (22, 17, 9, 2, '2026-10-23 11:15', 1000),
    (23, 17, 3, 2, '2026-10-23 11:15', 1200),
    (24, 18, 2, 2, '2026-10-31 11:30', 800),
    (25, 19, 6, 2, '2026-10-31 13:10', 2000),
    (26, 19, 7, 2, '2026-10-31 13:10', 1600),
    (27, 20, 1, 2, '2026-11-05 12:45', 1500),
    (28, 20, 3, 2, '2026-11-05 12:45', 1200),
    (29, 20, 5, 2, '2026-11-05 12:45', 600),
    (30, 21, 4, 2, '2026-11-05 14:45', 2500),
    (31, 21, 2, 2, '2026-11-05 14:45', 800),
    (32, 22, 6, 2, '2026-11-06 11:30', 2000),
    (33, 23, 6, 1, '2026-11-06 13:10', 2000),
    (34, 23, 7, 2, '2026-11-06 13:10', 1600),
    (35, 28, 1, 3, '2026-10-22 08:40', 1500),
    (36, 31, 3, 3, '2026-11-02 09:45', 1200),
    (37, 32, 1, 3, '2026-11-05 09:00', 1500),
    (38, 32, 5, 3, '2026-11-05 09:00', 600),
    (39, 33, 7, 3, '2026-11-05 10:40', 1600),
    (40, 34, 10, 3, '2026-11-09 10:00', 2800),
    (41, 36, 8, 3, '2026-11-10 13:00', 7500),
    (42, 41, 6, 4, '2026-10-19 11:10', 2000),
    (43, 41, 7, 4, '2026-10-19 11:10', 1600),
    (44, 42, 10, 4, '2026-10-19 12:40', 2600),
    (45, 43, 6, 4, '2026-10-21 11:10', 2000),
    (46, 43, 7, 4, '2026-10-21 11:10', 1600),
    (47, 44, 4, 4, '2026-10-21 13:40', 2300),
    (48, 44, 2, 4, '2026-10-21 13:40', 800),
    (49, 47, 6, 4, '2026-10-31 11:40', 2000),
    (50, 47, 7, 4, '2026-10-31 11:40', 1600),
    (51, 48, 1, 4, '2026-10-31 13:10', 1500),
    (52, 48, 5, 4, '2026-10-31 13:10', 600),
    (53, 49, 6, 4, '2026-11-02 11:40', 2000),
    (54, 49, 7, 4, '2026-11-02 11:40', 1600),
    (55, 50, 1, 4, '2026-11-02 13:20', 1500),
    (56, 50, 9, 4, '2026-11-02 13:20', 1000),
    (57, 51, 7, 4, '2026-11-07 11:40', 1600),
    (58, 52, 3, 4, '2026-11-07 13:25', 1200),
    (59, 53, 8, 4, '2026-11-09 12:30', 7500),
    (60, 54, 4, 4, '2026-11-09 14:30', 2500),
    (61, 55, 1, 4, '2026-11-13 11:10', 1500),
    (62, 55, 9, 4, '2026-11-13 11:10', 1000),
    (63, 57, 2, 5, '2026-09-08 10:30', 800),
    (64, 58, 2, 5, '2026-09-08 12:00', 800),
    (65, 59, 1, 5, '2026-09-14 10:10', 1500),
    (66, 60, 4, 5, '2026-09-14 11:40', 2300),
    (67, 61, 1, 5, '2026-09-15 09:40', 1500),
    (68, 62, 6, 5, '2026-09-15 11:50', 2000),
    (69, 62, 7, 5, '2026-09-15 11:50', 1600),
    (70, 63, 9, 5, '2026-09-25 11:15', 1000),
    (71, 63, 3, 5, '2026-09-25 11:15', 1200),
    (72, 2, 5, 1, '2026-10-19 15:30', 600);

COMMIT;


-- ---------------------------------------------------------------------------
-- Примеры запросов (не выполняются, приведены для проверки модели)
-- ---------------------------------------------------------------------------
-- Зарплата мастеров за октябрь 2026 г. (процент от выручки у каждого свой):
--   SELECT m.last_name, SUM(w.price) AS revenue,
--          ROUND(SUM(w.price) * m.salary_percent / 100, 2) AS salary
--   FROM masters m JOIN performed_works w ON w.master_id = m.id
--   WHERE w.performed_at >= '2026-10-01' AND w.performed_at < '2026-11-01'
--   GROUP BY m.id ORDER BY m.last_name;
--
-- Работающие и уволенные мастера:
--   SELECT last_name, first_name, CASE WHEN dismissal_date IS NULL THEN 'работает' ELSE 'уволен' END AS state
--   FROM masters ORDER BY dismissal_date IS NOT NULL, last_name;
--
-- Выручка по услугам:
--   SELECT s.name, COUNT(*) AS cnt, SUM(w.price) AS revenue
--   FROM performed_works w JOIN services s ON s.id = w.service_id
--   GROUP BY s.id ORDER BY revenue DESC;
