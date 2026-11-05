/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Бушмина Ольга
 * Дата: 25.11.2024
*/

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
        total_area < (SELECT total_area_limit FROM limits)
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
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
spb_or_obl as(
     SELECT *,
            CASE WHEN city_id = '6X8I' 
                 THEN 'Санкт-Петербург'
                 ELSE 'ЛенОбласть'
            END AS region_cat,
            CASE WHEN days_exposition >=181 THEN '6 месяцев и более'
                 WHEN days_exposition >=91 THEN '3-6 месяцев'
		       WHEN days_exposition >31 THEN '1-3 месяца'
                 WHEN days_exposition >=0 THEN '1 месяц и менее'
                 WHEN days_exposition ISNULL THEN 'активно сейчас'
            END AS active_cat,
            last_price/total_area*1.0 AS one_metr_price
      FROM real_estate.flats AS f
      LEFT JOIN real_estate.advertisement a using(id)
      WHERE id IN (SELECT * FROM filtered_id) AND type_id = 'F8EM'
)
SELECT region_cat, 
       active_cat,
       COUNT(id) AS count_advert,
       ROUND(Count(id)*100.0/SUM(COUNT(id))OVER(PARTITION BY region_cat),1) AS prop_in_region,
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
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
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
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
months_exp as(
     SELECT
            id,
            extract(MONTH FROM first_day_exposition) AS open_month,
            extract(MONTH FROM (first_day_exposition + (days_exposition || ' days')::INTERVAL)) AS close_month,
            days_exposition,
            last_price, 
            f.total_area,
            last_price / f.total_area AS metr_price
      FROM real_estate.advertisement AS a
      LEFT JOIN real_estate.flats f USING(id)
      WHERE id IN (SELECT * FROM filtered_id) AND days_exposition IS NOT NULL AND (first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31')
),
gruppi_open as(
      SELECT open_month AS month_number,
             COUNT(last_price) AS count_op, --количество поданых объявлений за месяц 
             DENSE_RANK() OVER(ORDER BY count(last_price) DESC) AS rank_count_op, --ранг месяца по количеству открытых объявлений
             AVG(total_area) AS avg_area, --средняя площадь квартиры
             PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY total_area) AS medi_area, --медиана площади квартиры
             AVG(metr_price) AS avg_metr_pr, --средняя цена кв.метра
             PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY metr_price) AS medi_one_metr --медиана цены за кв.метр
      FROM months_exp
      GROUP BY open_month
),
gruppi_close as(
      SELECT close_month AS month_number,
             COUNT(last_price) AS count_close, --количество закрытых объявлений за месяц 
             DENSE_RANK() OVER(ORDER BY count(last_price) DESC) AS rank_count_cl --ранг месяца по числу закрытых объявлений
      FROM months_exp
      GROUP BY close_month
)
SELECT CASE WHEN month_number = 1 THEN 'Январь' 
            WHEN month_number = 2 THEN 'Февраль' 
            WHEN month_number = 3 THEN 'Март' 
            WHEN month_number = 4 THEN 'Апрель' 
            WHEN month_number = 5 THEN 'Май' 
            WHEN month_number = 6 THEN 'Июнь' 
            WHEN month_number = 7 THEN 'Июль' 
            WHEN month_number = 8 THEN 'Август' 
            WHEN month_number = 9 THEN 'Сентябрь' 
            WHEN month_number = 10 THEN 'Октябрь' 
            WHEN month_number = 11 THEN 'Ноябрь' 
            WHEN month_number = 12 THEN 'Декабрь' 
            END AS month_name,
       CASE WHEN rank_count_op >=1 AND rank_count_op <5 THEN 'Высокая активность'
            WHEN rank_count_op >=5 AND rank_count_op <9 THEN 'Средняя активность'
            WHEN rank_count_op >=9 THEN 'Низкая активность'
            END AS rank_activity,
       rank_count_op,
       count_op,
       ROUND(count_op / SUM(count_op) OVER()*100, 2) AS prop_open,
       avg_area::NUMERIC(10, 2),
       medi_area::NUMERIC(10, 2),
       avg_metr_pr::NUMERIC(10, 2),
       medi_one_metr::NUMERIC(10, 2),
       rank_count_cl,
       count_close,
       ROUND(count_close / SUM(count_close) OVER()*100, 2) AS prop_close
FROM gruppi_open AS go
LEFT JOIN gruppi_close AS gc USING (month_number)
ORDER BY rank_count_op;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

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
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
)
SELECT
       t.type,
       c.city,
	  COUNT(a.id) AS count_open,
	  ROUND(COUNT(id) FILTER (WHERE days_exposition IS NOT null)/count(a.id)::numeric*100, 2) AS prop_close,
	  ROUND(AVG(a.days_exposition)::NUMERIC,0) AS avg_days_exp,
	  ROUND(AVG(a.last_price/f.total_area*1.0)::NUMERIC,2) AS avg_price_metr,
	  ROUND(AVG(f.total_area)::NUMERIC,2) AS avg_total_area,
	  PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY rooms) AS medi_rooms, 
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY balcony) AS medi_balc,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floor) AS medi_floor,
       PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floors_total) AS medi_flo_total
FROM real_estate.advertisement a
JOIN filtered_flats f using(id)
LEFT JOIN real_estate.city c using(city_id)
LEFT JOIN real_estate.type t using(type_id)
WHERE city_id != '6X8I'
GROUP BY  c.city, t.type
ORDER BY count_open DESC
LIMIT 15