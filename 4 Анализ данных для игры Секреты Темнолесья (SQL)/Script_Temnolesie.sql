/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Бушмина Ольга
 * Дата: 05.11.2024
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Из таблицы users находим долю платящих игроков как отношение кол-ва плативших игроков к кол-ву всех зарегистрированных пользователей 
SELECT COUNT(id) AS total_users,
       SUM(payer) AS payers,
       SUM(payer)*1.0/COUNT(id) AS prop_payers
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Для каждой расы рассчитаем кол-во платящих игроков, кол-во зарегистрованных пользователей,долю платящих юзеров и процент платящих юзеров для наглядности
SELECT r.race AS race_name,
       SUM(u.payer) AS payers_by_race,
       COUNT(u.id) AS total_race_users,
       SUM(u.payer)*1.0/COUNT(id) AS prop_payers_by_race,
       ROUND(SUM(u.payer)*100.0/COUNT(id), 2) AS proc_payer_by_race
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r USING(race_id)
GROUP BY r.race
ORDER BY total_race_users DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Из таблицы events находим: общее кол-во покупок, суммарную стоимость покупок, минимальную, максимальную, среднюю стоимость покупки.
-- Также медиану как второй квартиль и стандартное отклонение.
SELECT COUNT(amount) AS count_events, 
	   SUM(amount) AS sum_amount,    
	   MIN(amount) AS min_amount,     
	   MAX(amount) AS max_amount,     
	   AVG(amount) AS avg_amount, 
	   PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY amount) AS median_amount,
	   STDDEV(amount) AS stand_dev
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
-- Подсчитываем кол-во покупок с ценой сделки = 0, а также их долю от общего количества покупок
SELECT (SELECT COUNT(*)   
        FROM fantasy.events
        WHERE amount = 0),
       (SELECT COUNT(*)   
        FROM fantasy.events
        WHERE amount = 0)*1.0 / COUNT(amount) AS prop
FROM fantasy.events;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Анализируем поведение платящих и неплатящих игроков: общее количество игроков, средние стоимость и количество покупок
-- Используя LEFT JOIN, считаем всех пользователей, включая тех, кто, например, платил, но не совершал покупки
-- Чтобы выбрать количество платящих, кто еще и купил, использовала бы inner join
WITH events_for_user AS(
   SELECT id,
          COUNT(amount) AS count_for_user,
   		  SUM(amount) AS sum_for_user
   FROM fantasy.events 
   GROUP BY id
)
SELECT u.payer,
       COUNT(u.payer),
       ROUND(AVG(ev.count_for_user), 2) AS avg_count,
       ROUND(AVG(ev.sum_for_user)::numeric, 2) AS avg_amount
FROM fantasy.users AS u
LEFT JOIN events_for_user AS ev USING(id)
GROUP BY payer;

-- 2.4: Популярные эпические предметы:
-- В cte выделяем покупки с ненулевой суммой, будем учитывать только их. 
-- По каждому эпическому предмету находим количество продаж, долю от общих ненулевых продаж, количество уникальных игроков,
-- которые хотя бы раз купили предмет и долю от общего количества игроков с ненулевыми покупками.
WITH not_zero_amounts AS(
     SELECT id,
            item_code,
            amount
     FROM fantasy.events 
     WHERE amount > 0
)
SELECT  i.item_code,
        i.game_items,
        COUNT(n.amount) AS count_by_item,
        COUNT(n.amount)*1.0 / (SELECT COUNT(*) FROM not_zero_amounts) AS prop_by_item,
        COUNT(DISTINCT n.id) AS count_players,
        COUNT(DISTINCT n.id)*1.0 / (SELECT COUNT(DISTINCT id) FROM not_zero_amounts) AS prop_players
FROM fantasy.items AS i
LEFT JOIN not_zero_amounts AS n using(item_code)
GROUP BY item_code, game_items 
ORDER BY count_by_item DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH not_zero_amounts AS( --список ненулевых продаж
     SELECT id, --id игрока
            amount --сумма покупки
     FROM fantasy.events 
     WHERE amount > 0
),
users_calc AS ( --количество зарегистр.игроков
       SELECT race_id,
              COUNT(DISTINCT id) AS total_users -- количество зарегистрированных игроков
       FROM fantasy.users
       GROUP BY race_id
),
buyers_calc AS ( -- расчет ненулевых покупающих юзеров по расам
     SELECT race_id,
            COUNT(DISTINCT n.id) AS total_buyers
     FROM fantasy.users AS u
     LEFT JOIN not_zero_amounts AS n USING(id)
     GROUP BY race_id
),
payers_calc AS( -- расчет количества платящих юзеров по расам
     SELECT race_id,
            SUM(payer) AS total_payers
     FROM fantasy.users
     GROUP BY race_id
),
events_for_user AS(
   SELECT id, 
          COUNT(amount) AS count_for_user, --количество покупок одного юзера
   		  SUM(amount) AS sum_for_user, -- сумма покупок одного юзера
   		  AVG(amount) AS avg_for_user -- средняя стоимость одной покупки одного игрока
   FROM fantasy.events 
   WHERE amount>0
   GROUP BY id
),
avg_calc AS(
	SELECT u.race_id,
      	   ROUND(AVG(ev.count_for_user), 2) AS avg_count_amount, --среднее количество ненулевых покупок одного юзера
       	   ROUND(AVG(ev.sum_for_user)::numeric, 2) AS avg_total_amount, --средняя суммарная стоимость всех покупок на одного игрока
       	   ROUND(AVG(avg_for_user)::numeric, 2) AS avg_one_amount -- средняя стоимость одной покупки одного игрока
FROM fantasy.users AS u
LEFT JOIN events_for_user AS ev USING(id)
GROUP BY u.race_id
)
SELECT uc.race_id,
       r.race,
       uc.total_users, -- количество зарегистрированных игроков
       b.total_buyers, -- количество игроков с ненулевыми покупками
       ROUND(b.total_buyers*1.0 / uc.total_users, 3) AS prop_buyers, --доля покупающих по каждой расе от общего количества юзеров
       p.total_payers, -- количество платящих игроков
       ROUND(p.total_payers*1.0/ b.total_buyers, 3) AS prop_pay_buy, -- доля платящих юзеров от покупающих юзеров
       a.avg_count_amount, -- среднее количество ненулевых покупок на 1 игрока
       a.avg_one_amount, -- средняя стоимость одной ненулевой покупки одного игрока
       a.avg_total_amount -- средняя суммарная стоимость всех покупок на одного игрока
FROM users_calc AS uc 
LEFT JOIN payers_calc AS p USING(race_id)
LEFT JOIN buyers_calc AS b USING(race_id)
LEFT JOIN fantasy.race AS r USING(race_id)
LEFT JOIN avg_calc AS a USING(race_id)
ORDER BY total_users DESC;

-- Задача 2: Частота покупок
WITH not_zero_amounts AS( -- Выделяем ненулевые покупки
     SELECT *
     FROM fantasy.events 
     WHERE amount > 0
),
lag_print AS ( -- Находим дату предыдущего заказа юзера
	 SELECT id,
      	    transaction_id,
            amount,
            date,
            LAG(date) OVER(PARTITION BY id ORDER BY date) AS previous_amount_date
	 FROM not_zero_amounts
	 ORDER BY id, date
),
lag_calc AS ( -- Вычисляем количество дней между соседними заказами
     SELECT id,
            transaction_id,
            amount,
            date,
            previous_amount_date,
            CASE WHEN (date::date-previous_amount_date::date) IS NULL
                 THEN '0'
                 ELSE (date::date-previous_amount_date::date)
                 END AS days_before
     FROM lag_print
),
for_user AS ( -- На каждого пользователя рассчитываем количество покупок и средний интервал заказа, оставляем активных
     SELECT id,
            u.payer,
            COUNT(amount) AS count_per_user,
            ROUND(AVG(days_before),4) AS avg_days
     FROM lag_calc
     LEFT JOIN fantasy.users AS u USING(id)
     GROUP BY id, u.payer
     HAVING COUNT(amount)>=25
),
ranking AS ( -- разделяем пользователей на 3 группы по ачастоте заказов
     SELECT *,
     NTILE(3) OVER(ORDER BY avg_days) AS group_rank
     FROM for_user
),
naming_rank AS ( --переименовываем группы
     SELECT *,
            CASE WHEN group_rank = 1
                      THEN 'высокая частота'
                 WHEN group_rank = 2
                      THEN 'средняя частота'
                 WHEN group_rank = 3
                      THEN 'низкая частота'
            END AS name_rank
     FROM ranking 
     ORDER BY group_rank
),
calculation AS ( -- рассчитываем стастику по группам
     SELECT group_rank,
            name_rank,
            COUNT(id) AS count_users,
            SUM(payer) AS payers,
            ROUND(SUM(payer)*1.0 / COUNT(id), 3) AS prop_payers,
            ROUND(AVG(count_per_user), 3) AS avg_count_amount,
            ROUND(AVG(avg_days), 3) AS avg_days_group  
     FROM naming_rank
     GROUP BY group_rank, name_rank
     ORDER BY group_rank
)
SELECT *
FROM calculation;

