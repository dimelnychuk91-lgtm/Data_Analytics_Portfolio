-- 1. Розраховуємо основні метрики по акаунтам
WITH
account_metrics AS (
  SELECT
    CAST(s.date AS DATE) AS date,
    sp.country,
    a.send_interval,
    a.is_verified,
    a.is_unsubscribed,
    COUNT(a.id) AS account_cnt,
    0 AS sent_msg,
    0 AS open_msg,
    0 AS visit_msg
  FROM `data-analytics-mate.DA.account` a
  JOIN `data-analytics-mate.DA.account_session` acs ON a.id = acs.account_id
  JOIN `data-analytics-mate.DA.session` s ON acs.ga_session_id = s.ga_session_id
  JOIN `data-analytics-mate.DA.session_params` sp ON acs.ga_session_id = sp.ga_session_id
  GROUP BY 1, 2, 3, 4, 5
),


-- 2. Розраховуємо основні метрики по емейлам
email_metrics AS (
  SELECT
    -- Витягуємо дату
    DATE_ADD(CAST(s.date AS DATE), INTERVAL es.sent_date DAY) AS date,
    sp.country,
    a.send_interval,
    a.is_verified,
    a.is_unsubscribed,
    0 AS account_cnt,                        
    COUNT(DISTINCT es.id_message) AS sent_msg,
    COUNT(DISTINCT eo.id_message) AS open_msg,
    COUNT(DISTINCT ev.id_message) AS visit_msg  
  FROM `data-analytics-mate.DA.email_sent` es
  -- Підтягуємо інфо про власника емейлу
  JOIN `data-analytics-mate.DA.account` a ON es.id_account = a.id
  JOIN `data-analytics-mate.DA.account_session` acs ON a.id = acs.account_id
  JOIN `data-analytics-mate.DA.session` s ON acs.ga_session_id = s.ga_session_id
  JOIN `data-analytics-mate.DA.session_params` sp ON acs.ga_session_id = sp.ga_session_id
  -- Приєднуємо події: відкриття та кліки.
  LEFT JOIN `data-analytics-mate.DA.email_open` eo ON es.id_message = eo.id_message
  LEFT JOIN `data-analytics-mate.DA.email_visit` ev ON es.id_message = ev.id_message
  GROUP BY 1, 2, 3, 4, 5
),


-- 3. Об'єднуємо та агрегуємо метрики
unioned_data AS (
  SELECT * FROM account_metrics
  UNION ALL
  SELECT * FROM email_metrics
),


aggregated_data AS (
  SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    -- Сумуємо, щоб звести рядки з UNION в один
    SUM(account_cnt) AS account_cnt,
    SUM(sent_msg) AS sent_msg,
    SUM(open_msg) AS open_msg,
    SUM(visit_msg) AS visit_msg
  FROM unioned_data
  GROUP BY 1, 2, 3, 4, 5
),


-- 4. Розраховуємо додаткові метрики (тотали по країнам)
window_data AS (
  SELECT
    *,
    -- Скільки всього акаунтів у цій країні (сума стовпчика account_cnt для всієї країни)
    SUM(account_cnt) OVER(PARTITION BY country) AS total_country_account_cnt,
    -- Скільки всього листів у цій країні
    SUM(sent_msg) OVER(PARTITION BY country) AS total_country_sent_cnt
  FROM aggregated_data
),


-- 5. Розраховуємо ранки за допомогою DENSE_RANK
ranked_data AS (
  SELECT
    *,
    -- Ранжуємо країни за кількістю акаунтів
    DENSE_RANK() OVER(ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
    -- Ранжуємо країни за кількістю листів
    DENSE_RANK() OVER(ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt
  FROM window_data
)
-- 6. Виводимо всі дані з умовою по ранкам
SELECT
  *
FROM ranked_data
WHERE
  rank_total_country_account_cnt <= 10
  OR rank_total_country_sent_cnt <= 10
ORDER BY
  country, date;
