/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Бушмина Ольга
 * Дата: 25.11.2024
*/

-- Статическая доработка для портфолио. Запросы не выполнены: учебная БД недоступна.
-- Снятие объявления с публикации не подтверждает продажу.
-- NULL в days_exposition означает неизвестный срок, а не доказанно активное объявление.
-- Сохранены исходные строгие границы перцентилей (< p99, > p01).
-- Значения на границе исключаются; NULL rooms/balcony/ceiling_height допускаются.
-- Пороги оцениваются по всей flats, без пересчёта по регионам и периодам.


-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area > 0
        AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Исходные интервалы сохранены: 0–31, >31–<91, 91–<181, >=181 дней.
-- type_id = 'F8EM' — исходное ограничение на тип населённого пункта (город).
-- INNER JOIN исключает квартиры без соответствующего объявления.
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area > 0
        AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
spb_or_obl as(
     SELECT f.id, f.total_area, f.rooms, f.balcony, f.floor,
            f.floors_total, f.is_apartment, f.open_plan,
            CASE WHEN f.city_id = '6X8I' 
                 THEN 'Санкт-Петербург'
                 ELSE 'ЛенОбласть'
            END AS region_cat,
            CASE WHEN a.days_exposition >=181 THEN '6 месяцев и более'
                 WHEN a.days_exposition >=91 THEN '3-6 месяцев'
		       WHEN a.days_exposition >31 THEN '1-3 месяца'
                 WHEN a.days_exposition >=0 THEN '1 месяц и менее'
                 WHEN a.days_exposition IS NULL THEN 'срок не указан'
            END AS active_cat,
            a.last_price::numeric / NULLIF(f.total_area::numeric, 0) AS one_metr_price
      FROM real_estate.flats AS f
      JOIN real_estate.advertisement AS a ON a.id = f.id
      WHERE f.id IN (SELECT id FROM filtered_id) AND f.type_id = 'F8EM'
        AND (a.days_exposition >= 0 OR a.days_exposition IS NULL)
)
SELECT region_cat, 
       active_cat,
       COUNT(id) AS count_advert,
       ROUND(COUNT(id)::numeric * 100 / NULLIF(SUM(COUNT(id)) OVER (PARTITION BY region_cat), 0), 1) AS prop_in_region,
       ROUND(avg(one_metr_price)::numeric,2) AS avg_price_metr,
       ROUND(avg(total_area)::NUMERIC,2) AS avg_total_area,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY rooms) AS medi_rooms, 
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY balcony) AS medi_balc,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floor) AS medi_floor,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floors_total) AS medi_flo_total,
       SUM(is_apartment) AS apart_count,
       SUM(open_plan) AS open_plan_count
FROM spb_or_obl
GROUP BY region_cat, active_cat
ORDER BY region_cat DESC, active_cat;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это характеризует активность объявлений.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда снимается больше объявлений? Дата снятия не является датой сделки.
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area > 0
        AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Публикации и снятия считаются по собственной дате события за полные 2015–2018 годы.
-- В отличие от исходника, публикации включают объявления с неизвестным сроком.
-- Снятия не ограничиваются годом публикации; это может изменить результаты DOCX.
months_exp AS (
    SELECT a.id,
           a.first_day_exposition AS open_date,
           a.first_day_exposition
               + a.days_exposition * INTERVAL '1 day' AS close_date,
           f.total_area,
           a.last_price::numeric / NULLIF(f.total_area::numeric, 0) AS metr_price
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON f.id = a.id
    WHERE f.id IN (SELECT id FROM filtered_id)
      AND (a.days_exposition >= 0 OR a.days_exposition IS NULL)
),
gruppi_open AS (
    SELECT EXTRACT(MONTH FROM open_date)::integer AS month_number,
           COUNT(*) AS count_op,
           AVG(total_area) AS avg_area,
           PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY total_area) AS medi_area,
           AVG(metr_price) AS avg_metr_pr,
           PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY metr_price) AS medi_one_metr
    FROM months_exp
    WHERE open_date >= DATE '2015-01-01' AND open_date < DATE '2019-01-01'
    GROUP BY EXTRACT(MONTH FROM open_date)
),
gruppi_close AS (
    SELECT EXTRACT(MONTH FROM close_date)::integer AS month_number,
           COUNT(*) AS count_close
    FROM months_exp
    WHERE close_date >= DATE '2015-01-01' AND close_date < DATE '2019-01-01'
    GROUP BY EXTRACT(MONTH FROM close_date)
),
-- Сетка месяцев сохраняет месяцы без событий и независимые знаменатели долей.
month_stats AS (
    SELECT m.month_number,
           COALESCE(go.count_op, 0) AS count_op,
           COALESCE(gc.count_close, 0) AS count_close,
           go.avg_area, go.medi_area, go.avg_metr_pr, go.medi_one_metr
    FROM generate_series(1, 12) AS m(month_number)
    LEFT JOIN gruppi_open AS go ON go.month_number = m.month_number
    LEFT JOIN gruppi_close AS gc ON gc.month_number = m.month_number
),
ranked AS (
    SELECT *,
           DENSE_RANK() OVER (ORDER BY count_op DESC) AS rank_count_op,
           DENSE_RANK() OVER (ORDER BY count_close DESC) AS rank_count_cl
    FROM month_stats
)
SELECT month_number,
       (ARRAY['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
              'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'])[month_number]
           AS month_name,
       CASE WHEN rank_count_op < 5 THEN 'Высокая активность'
            WHEN rank_count_op < 9 THEN 'Средняя активность'
            ELSE 'Низкая активность'
       END AS rank_activity,
       rank_count_op, count_op,
       ROUND(count_op::numeric * 100 / NULLIF(SUM(count_op) OVER (), 0), 2) AS prop_open,
       avg_area::numeric(10, 2),
       medi_area::numeric(10, 2),
       avg_metr_pr::numeric(10, 2),
       medi_one_metr::numeric(10, 2),
       rank_count_cl, count_close,
       ROUND(count_close::numeric * 100 / NULLIF(SUM(count_close) OVER (), 0), 2) AS prop_close
FROM ranked
ORDER BY rank_count_op, month_number;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это доля объявлений с известным сроком, не доля подтверждённых сделок.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    Сравниваем сроки размещения; причины снятия и фактические сделки неизвестны.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_flats AS (
    SELECT *
    FROM real_estate.flats  
    WHERE 
        total_area > 0
        AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
)
SELECT
       t.type,
       c.city,
	  COUNT(a.id) AS count_open,
	  ROUND(COUNT(a.id) FILTER (WHERE a.days_exposition IS NOT NULL)::numeric
            * 100 / NULLIF(COUNT(a.id), 0), 2) AS prop_close,
	  ROUND(AVG(a.days_exposition)::NUMERIC,0) AS avg_days_exp,
	  ROUND(AVG(a.last_price::numeric / NULLIF(f.total_area::numeric, 0))::NUMERIC,2) AS avg_price_metr,
	  ROUND(AVG(f.total_area)::NUMERIC,2) AS avg_total_area,
	  PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY f.rooms) AS medi_rooms, 
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY f.balcony) AS medi_balc,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY f.floor) AS medi_floor,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY f.floors_total) AS medi_flo_total
FROM real_estate.advertisement a
JOIN filtered_flats AS f ON f.id = a.id
LEFT JOIN real_estate.city AS c ON c.city_id = f.city_id
LEFT JOIN real_estate.type AS t ON t.type_id = f.type_id
-- Сохранено исходное деление по city_id: это не проверка административных границ ЛО.
WHERE f.city_id != '6X8I'
  AND (a.days_exposition >= 0 OR a.days_exposition IS NULL)
GROUP BY f.city_id, f.type_id, c.city, t.type
ORDER BY count_open DESC, c.city, t.type, f.city_id, f.type_id
LIMIT 15;
